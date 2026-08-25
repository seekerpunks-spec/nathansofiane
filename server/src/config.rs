//! Remote config — chargement, versionnage (SHA-256) et validation au boot.
//!
//! Règle d'or (GDD §40, ARCH §5) : aucune valeur économique dans le code.
//! Tout est lu ici depuis `config/`. Le serveur REFUSE de démarrer sur une
//! config invalide.

use anyhow::{anyhow, bail, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

/// Fichiers de premier niveau attendus dans le répertoire config.
const TOP_LEVEL_FILES: &[&str] = &[
    "achievements.json",
    "cards.json",
    "chests.json",
    "daily.json",
    "economy.json",
    "entitlements.json",
    "events.json",
    "offers.json",
    "progression.json",
    "reward_pool.json",
    "seasons.json",
    "sets.json",
    "social.json",
    "spin_table.json",
];

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AdsConfig {
    pub max_rewarded_ads_per_day: u32,
    pub reward_per_ad: u32,
    pub cooldown_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EconomyConfig {
    pub spin_regen_ms: u64,
    pub max_free_spins: u32,
    pub new_player_spins: u32,
    pub spin_multipliers: Vec<u32>,
    pub ads_config: AdsConfig,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OutcomeType {
    Credits,
    Chest,
    Card,
    Attack,
    Raid,
    Shield,
    None,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Tier {
    Common,
    Uncommon,
    Rare,
    Epic,
    Legendary,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpinOutcome {
    pub id: String,
    #[serde(rename = "type")]
    pub outcome_type: OutcomeType,
    pub tier: Tier,
    pub weight: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub min: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(default, rename = "rewardId", skip_serializing_if = "Option::is_none")]
    pub reward_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpinTable {
    pub outcomes: Vec<SpinOutcome>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AttackConfig {
    pub base_reward_credits: u64,
    pub blocked_reward_credits: u64,
    pub repair_cost_bps: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RaidConfig {
    pub node_count: u32,
    pub max_picks: u32,
    pub trace_nodes: u32,
    pub base_pot_credits: u64,
    pub protected_credits: u64,
    pub max_steal_bps: u32,
    pub safe_node_shares_bps: Vec<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SocialConfig {
    pub firewall_max_charges: u32,
    pub shield_overflow_credits: u64,
    pub encounter_ttl_ms: u64,
    pub target_preference_ttl_ms: u64,
    pub revenge_window_ms: u64,
    pub teams: TeamConfig,
    pub trading: TradingConfig,
    pub attack: AttackConfig,
    pub raid: RaidConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TeamConfig {
    pub max_members: u32,
    pub create_cost_credits: u64,
    pub search_limit: u32,
    pub leaderboard_limit: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TradingConfig {
    pub offer_ttl_ms: u64,
    pub max_pending_per_player: u32,
    pub min_quantity_to_trade: u32,
    pub history_limit: u32,
    pub tradeable_rarities: Vec<Tier>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RarityPointsConfig {
    pub common: u32,
    pub uncommon: u32,
    pub rare: u32,
    pub epic: u32,
    pub legendary: u32,
}

impl RarityPointsConfig {
    pub fn points(&self, tier: Tier) -> u32 {
        match tier {
            Tier::Common => self.common,
            Tier::Uncommon => self.uncommon,
            Tier::Rare => self.rare,
            Tier::Epic => self.epic,
            Tier::Legendary => self.legendary,
        }
    }
}

/// Enveloppe de progression des districts. Les coûts restent écrits dans chaque
/// fichier de district ; cette courbe borne ce qui est acceptable pour éviter
/// qu'un nouveau district dérive silencieusement de l'équilibrage.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DistrictCurveConfig {
    pub base_district_cost_credits: u64,
    pub district_cost_growth: f64,
    pub district_cost_tolerance: f64,
    pub level_cost_growth_min: f64,
    pub level_cost_growth_max: f64,
    pub expected_spins_min: f64,
    pub expected_spins_max: f64,
    pub expected_spins_growth: f64,
}

impl DistrictCurveConfig {
    /// Coût total attendu pour un district, `id` étant 1-indexé.
    pub fn expected_district_cost(&self, id: u32) -> f64 {
        self.base_district_cost_credits as f64 * self.district_cost_growth.powi(id as i32 - 1)
    }

    /// Écart relatif entre un coût total observé et la courbe attendue.
    /// C'est la forme unique de comparaison : borner puis comparer donnerait un
    /// résultat différent au bord de la tolérance en flottant.
    pub fn cost_deviation(&self, id: u32, total_credits: u128) -> f64 {
        let expected = self.expected_district_cost(id);
        if !(expected > 0.0) || !expected.is_finite() {
            return f64::INFINITY;
        }
        (total_credits as f64 - expected).abs() / expected
    }

    /// Fenêtre de spins attendue pour compléter un district, `id` étant 1-indexé.
    pub fn expected_spins_window(&self, id: u32) -> (f64, f64) {
        let factor = self.expected_spins_growth.powi(id as i32 - 1);
        (
            self.expected_spins_min * factor,
            self.expected_spins_max * factor,
        )
    }

    fn parameters_are_sane(&self) -> bool {
        self.base_district_cost_credits > 0
            && self.base_district_cost_credits <= i64::MAX as u64
            && self.district_cost_growth.is_finite()
            && self.district_cost_growth >= 1.0
            && self.district_cost_growth <= 10.0
            && self.district_cost_tolerance.is_finite()
            && self.district_cost_tolerance > 0.0
            && self.district_cost_tolerance < 1.0
            && self.level_cost_growth_min.is_finite()
            && self.level_cost_growth_min > 1.0
            && self.level_cost_growth_max.is_finite()
            && self.level_cost_growth_max > self.level_cost_growth_min
            && self.level_cost_growth_max <= 100.0
            && self.expected_spins_min.is_finite()
            && self.expected_spins_min > 0.0
            && self.expected_spins_max.is_finite()
            && self.expected_spins_max > self.expected_spins_min
            && self.expected_spins_growth.is_finite()
            && self.expected_spins_growth >= 1.0
            && self.expected_spins_growth <= 10.0
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgressionConfig {
    pub score_name: String,
    pub upgrade_points: u32,
    pub district_completion_points: u32,
    pub set_completion_points: u32,
    pub achievement_points: u32,
    pub rarity_points: RarityPointsConfig,
    pub global_leaderboard_limit: u32,
    pub district_curve: DistrictCurveConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailyEntry {
    pub day: u32,
    pub spins: u32,
    pub credits: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub chest: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailyConfig {
    pub cycle: Vec<DailyEntry>,
    pub bonus: DailyBonusConfig,
    #[serde(default)]
    pub missions: Vec<MissionConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DailyBonusConfig {
    pub bonus_id: String,
    pub name: String,
    pub outcomes: Vec<DailyBonusOutcome>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DailyBonusOutcome {
    pub outcome_id: String,
    pub name: String,
    pub weight: u32,
    pub reward: Reward,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AchievementConfig {
    pub achievement_id: String,
    pub name: String,
    pub description: String,
    pub action: String,
    pub target: u64,
    pub reward: Reward,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EntitlementPerks {
    #[serde(default)]
    pub daily_spin_bonus: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub badge_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EntitlementConfig {
    pub entitlement_id: String,
    pub name: String,
    pub enabled: bool,
    pub collection_address: String,
    pub verification_ttl_ms: u64,
    pub perks: EntitlementPerks,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RewardPoolRule {
    pub source: String,
    pub source_id: String,
    pub amount_u64: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SeasonRewardPool {
    pub pool_id: String,
    pub token_mint: String,
    pub starts_at_ms: i64,
    pub ends_at_ms: i64,
    pub budget_u64: u64,
    pub min_claim_u64: u64,
    pub rules: Vec<RewardPoolRule>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RewardPoolConfig {
    pub enabled: bool,
    pub settlement_enabled: bool,
    pub pools: Vec<SeasonRewardPool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Reward {
    #[serde(default)]
    pub spins: u32,
    #[serde(default)]
    pub credits: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub chest: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MissionConfig {
    pub mission_id: String,
    pub name: String,
    pub action: String,
    pub target: u64,
    pub reward: Reward,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CardConfig {
    pub card_id: String,
    pub set_id: String,
    pub name: String,
    pub rarity: Tier,
    pub drop_weight: u32,
    pub image: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SetConfig {
    pub set_id: String,
    pub name: String,
    pub cards: Vec<String>,
    pub completion_spins: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LootWeight {
    pub rarity: Tier,
    pub weight: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChestConfig {
    pub chest_id: String,
    pub name: String,
    pub image: String,
    pub price_credits: u64,
    pub cards_per_open: u32,
    pub loot_table: Vec<LootWeight>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EventPointSource {
    pub action: String,
    pub points: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EventRewardTier {
    pub min_rank: u32,
    pub max_rank: u32,
    pub reward: Reward,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EventMilestone {
    pub points: u64,
    pub reward: Reward,
    #[serde(default)]
    pub auto_claim: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TeamEventMilestone {
    pub points: u64,
    pub reward: Reward,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TeamEventConfig {
    pub name: String,
    pub min_contribution_points: u64,
    pub milestones: Vec<TeamEventMilestone>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EventLeaderboardConfig {
    pub cohort_size: u32,
    pub display_limit: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EventConfig {
    pub event_id: String,
    pub name: String,
    pub starts_at_ms: i64,
    pub ends_at_ms: i64,
    pub point_sources: Vec<EventPointSource>,
    #[serde(default)]
    pub milestones: Vec<EventMilestone>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub team: Option<TeamEventConfig>,
    pub leaderboard: EventLeaderboardConfig,
    pub reward_tiers: Vec<EventRewardTier>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OfferContent {
    #[serde(rename = "type")]
    pub content_type: String,
    pub amount: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OfferConfig {
    pub offer_id: String,
    pub name: String,
    pub kind: String,
    pub contents: Vec<OfferContent>,
    pub price_token: String,
    pub price_u64: u64,
    pub starts_at_ms: i64,
    pub ends_at_ms: i64,
    pub max_per_player: u32,
    #[serde(default)]
    pub eligibility: OfferEligibility,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OfferEligibility {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_account_age_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub min_district_index: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_district_index: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_spins: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub requires_event_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub min_inactivity_ms: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SeasonTier {
    pub points: u64,
    pub free_reward: Reward,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub premium_reward: Option<Reward>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SeasonConfig {
    pub season_id: String,
    pub name: String,
    pub starts_at_ms: i64,
    pub ends_at_ms: i64,
    pub tiers: Vec<SeasonTier>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CompletionReward {
    pub spins: u32,
    pub credits: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub chest: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DistrictLevel {
    pub level: u32,
    pub cost: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub asset: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DistrictElement {
    pub id: u32,
    pub name: String,
    pub levels: Vec<DistrictLevel>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DistrictUnlockRequirements {
    pub completed_district_id: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct District {
    pub id: u32,
    pub name: String,
    pub background: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unlock_requirements: Option<DistrictUnlockRequirements>,
    pub elements: Vec<DistrictElement>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completion_reward: Option<CompletionReward>,
}

/// Config complète, validée au boot.
pub struct RemoteConfig {
    pub version: String,
    pub hash: String,
    pub economy: EconomyConfig,
    pub spin_table: SpinTable,
    pub social: SocialConfig,
    pub progression: ProgressionConfig,
    pub reward_pool: RewardPoolConfig,
    pub daily: DailyConfig,
    pub achievements: Vec<AchievementConfig>,
    pub entitlements: Vec<EntitlementConfig>,
    pub districts: Vec<District>,
    pub cards: Vec<CardConfig>,
    pub sets: Vec<SetConfig>,
    pub chests: Vec<ChestConfig>,
    pub events: Vec<EventConfig>,
    pub offers: Vec<OfferConfig>,
    pub seasons: Vec<SeasonConfig>,
}

fn reward_fits_storage(reward: &Reward) -> bool {
    reward.spins <= i32::MAX as u32 && reward.credits <= i64::MAX as u64
}

fn get_entry<'a>(entries: &'a [(String, Vec<u8>)], rel: &str) -> Result<&'a [u8]> {
    entries
        .iter()
        .find(|(name, _)| name == rel)
        .map(|(_, bytes)| bytes.as_slice())
        .ok_or_else(|| anyhow!("fichier config manquant : {}", rel))
}

/// Valide qu'un stub plat est soit un tableau JSON, soit un objet avec `items[]`.
fn parse_flat_stub(name: &str, bytes: &[u8]) -> Result<Value> {
    let v: Value =
        serde_json::from_slice(bytes).with_context(|| format!("{} : JSON invalide", name))?;
    match &v {
        Value::Array(_) => Ok(v),
        Value::Object(obj) if obj.get("items").is_some_and(|i| i.is_array()) => Ok(v),
        _ => bail!(
            "{} : attendu un tableau JSON ou un objet avec un champ items[]",
            name
        ),
    }
}

fn parse_items<T: for<'de> Deserialize<'de>>(name: &str, bytes: &[u8]) -> Result<Vec<T>> {
    let value = parse_flat_stub(name, bytes)?;
    let items = match value {
        Value::Array(items) => items,
        Value::Object(mut obj) => obj
            .remove("items")
            .and_then(|v| v.as_array().cloned())
            .unwrap_or_default(),
        _ => Vec::new(),
    };
    serde_json::from_value(Value::Array(items))
        .with_context(|| format!("{} : items invalides", name))
}

impl RemoteConfig {
    /// Charge + valide la config depuis `dir`. Refuse le boot sur config invalide.
    pub fn load(dir: &Path) -> Result<Self> {
        // 1) Inventaire : fichiers de premier niveau + districts/*.json (triés).
        let mut entries: Vec<(String, Vec<u8>)> = Vec::new();
        for name in TOP_LEVEL_FILES {
            let p = dir.join(name);
            let bytes = fs::read(&p).with_context(|| format!("lecture {}", p.display()))?;
            entries.push((name.to_string(), bytes));
        }
        let districts_dir = dir.join("districts");
        let mut district_names: Vec<String> = fs::read_dir(&districts_dir)
            .with_context(|| format!("lecture {}", districts_dir.display()))?
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| n.ends_with(".json"))
            .collect();
        district_names.sort();
        for name in district_names {
            let p = districts_dir.join(&name);
            let bytes = fs::read(&p).with_context(|| format!("lecture {}", p.display()))?;
            entries.push((format!("districts/{}", name), bytes));
        }
        entries.sort_by(|a, b| a.0.cmp(&b.0));

        // 2) Versioning : SHA-256 sur (relpath + \0 + bytes) triés.
        let mut hasher = Sha256::new();
        for (rel, bytes) in &entries {
            hasher.update(rel.as_bytes());
            hasher.update(b"\0");
            hasher.update(bytes);
        }
        let digest = hasher.finalize();
        let hash: String = digest.iter().map(|b| format!("{:02x}", b)).collect();
        let version = hash[..16].to_string();

        // 3) Parse typé.
        let economy: EconomyConfig = serde_json::from_slice(get_entry(&entries, "economy.json")?)
            .context("economy.json invalide")?;
        let spin_table: SpinTable = serde_json::from_slice(get_entry(&entries, "spin_table.json")?)
            .context("spin_table.json invalide")?;
        let social: SocialConfig = serde_json::from_slice(get_entry(&entries, "social.json")?)
            .context("social.json invalide")?;
        let progression: ProgressionConfig =
            serde_json::from_slice(get_entry(&entries, "progression.json")?)
                .context("progression.json invalide")?;
        let reward_pool: RewardPoolConfig =
            serde_json::from_slice(get_entry(&entries, "reward_pool.json")?)
                .context("reward_pool.json invalide")?;
        let daily: DailyConfig = serde_json::from_slice(get_entry(&entries, "daily.json")?)
            .context("daily.json invalide")?;
        let achievements = parse_items(
            "achievements.json",
            get_entry(&entries, "achievements.json")?,
        )?;
        let entitlements = parse_items(
            "entitlements.json",
            get_entry(&entries, "entitlements.json")?,
        )?;
        let districts: Vec<District> = entries
            .iter()
            .filter(|(name, _)| name.starts_with("districts/"))
            .map(|(name, bytes)| {
                serde_json::from_slice::<District>(bytes)
                    .with_context(|| format!("{} : district invalide", name))
            })
            .collect::<Result<Vec<_>>>()?;
        let cards = parse_items("cards.json", get_entry(&entries, "cards.json")?)?;
        let sets = parse_items("sets.json", get_entry(&entries, "sets.json")?)?;
        let chests = parse_items("chests.json", get_entry(&entries, "chests.json")?)?;
        let events = parse_items("events.json", get_entry(&entries, "events.json")?)?;
        let offers = parse_items("offers.json", get_entry(&entries, "offers.json")?)?;
        let seasons = parse_items("seasons.json", get_entry(&entries, "seasons.json")?)?;

        let cfg = RemoteConfig {
            version,
            hash,
            economy,
            spin_table,
            social,
            progression,
            reward_pool,
            daily,
            achievements,
            entitlements,
            districts,
            cards,
            sets,
            chests,
            events,
            offers,
            seasons,
        };

        // 4) Validation (règles d'équilibre minimales au boot).
        cfg.validate()?;
        Ok(cfg)
    }

    fn validate(&self) -> Result<()> {
        let mut problems: Vec<String> = Vec::new();

        if self.economy.spin_regen_ms < 1000 {
            problems.push(format!(
                "economy.spinRegenMs {} < 1000 (regen trop rapide)",
                self.economy.spin_regen_ms
            ));
        }
        if self.economy.spin_regen_ms > i64::MAX as u64 {
            problems.push("economy.spinRegenMs dépasse la durée supportée".to_string());
        }
        if self.economy.max_free_spins == 0 {
            problems.push("economy.maxFreeSpins doit être > 0".to_string());
        }
        if self.economy.max_free_spins > i32::MAX as u32
            || self.economy.new_player_spins > i32::MAX as u32
            || self.economy.ads_config.reward_per_ad > i32::MAX as u32
        {
            problems.push("economy : une valeur de spins dépasse INTEGER".to_string());
        }
        let multipliers = &self.economy.spin_multipliers;
        if multipliers.first() != Some(&1)
            || multipliers.is_empty()
            || multipliers.iter().any(|m| *m == 0 || *m > 100_000)
            || multipliers.windows(2).any(|pair| pair[0] >= pair[1])
        {
            problems.push(
                "economy.spinMultipliers doit être strictement croissant, commencer à 1 et rester <= 100000"
                    .to_string(),
            );
        }

        let mut seen_ids = BTreeSet::new();
        for o in &self.spin_table.outcomes {
            if o.weight == 0 {
                problems.push(format!("spin_table.{} : weight doit être > 0", o.id));
            }
            if !seen_ids.insert(o.id.clone()) {
                problems.push(format!("spin_table : id '{}' en double", o.id));
            }
            if o.outcome_type == OutcomeType::Credits {
                match (o.min, o.max) {
                    (Some(min), Some(max))
                        if min <= max
                            && max <= i64::MAX as u64
                            && max
                                .checked_mul(
                                    self.economy.spin_multipliers.last().copied().unwrap_or(1)
                                        as u64,
                                )
                                .is_some_and(|scaled| scaled <= i64::MAX as u64) => {}
                    _ => problems.push(format!(
                        "spin_table.{} : bornes invalides ou gain multiplié hors BIGINT",
                        o.id
                    )),
                }
            }
        }
        if self.spin_table.outcomes.is_empty() {
            problems.push("spin_table.outcomes est vide".to_string());
        }
        let total_weight: u64 = self
            .spin_table
            .outcomes
            .iter()
            .map(|outcome| outcome.weight as u64)
            .sum();
        if total_weight == 0 || total_weight > u32::MAX as u64 {
            problems.push("spin_table : somme des poids hors u32".to_string());
        }
        for required in [
            OutcomeType::Attack,
            OutcomeType::Raid,
            OutcomeType::Shield,
            OutcomeType::Chest,
            OutcomeType::Card,
        ] {
            if !self
                .spin_table
                .outcomes
                .iter()
                .any(|outcome| outcome.outcome_type == required)
            {
                problems.push(format!("spin_table : outcome {:?} manquant", required));
            }
        }
        let max_multiplier = self.economy.spin_multipliers.last().copied().unwrap_or(1);
        if self.social.firewall_max_charges == 0
            || self.social.firewall_max_charges > i32::MAX as u32
            || self.social.encounter_ttl_ms < 30_000
            || self.social.encounter_ttl_ms > 86_400_000
            || self.social.target_preference_ttl_ms < 60_000
            || self.social.target_preference_ttl_ms > 604_800_000
            || self.social.revenge_window_ms < 3_600_000
            || self.social.revenge_window_ms > 2_592_000_000
            || self.social.teams.max_members < 2
            || self.social.teams.max_members > 100
            || self.social.teams.create_cost_credits > i64::MAX as u64
            || self.social.teams.search_limit == 0
            || self.social.teams.search_limit > 50
            || self.social.teams.leaderboard_limit == 0
            || self.social.teams.leaderboard_limit > 100
            || self.social.trading.offer_ttl_ms < 60_000
            || self.social.trading.offer_ttl_ms > 604_800_000
            || self.social.trading.max_pending_per_player == 0
            || self.social.trading.max_pending_per_player > 20
            || self.social.trading.min_quantity_to_trade < 2
            || self.social.trading.min_quantity_to_trade > 100
            || self.social.trading.history_limit == 0
            || self.social.trading.history_limit > 100
            || self.social.trading.tradeable_rarities.is_empty()
            || self.social.trading.tradeable_rarities.len() > 5
            || self
                .social
                .trading
                .tradeable_rarities
                .iter()
                .enumerate()
                .any(|(index, rarity)| {
                    self.social.trading.tradeable_rarities[index + 1..].contains(rarity)
                })
            || self.social.attack.repair_cost_bps == 0
            || self.social.attack.repair_cost_bps > 10_000
            || self.social.raid.node_count < 4
            || self.social.raid.node_count > 12
            || self.social.raid.max_picks == 0
            || self.social.raid.max_picks >= self.social.raid.node_count
            || self.social.raid.trace_nodes == 0
            || self.social.raid.trace_nodes >= self.social.raid.node_count
            || self.social.raid.max_steal_bps == 0
            || self.social.raid.max_steal_bps > 10_000
            || self.social.raid.safe_node_shares_bps.len()
                != (self.social.raid.node_count - self.social.raid.trace_nodes) as usize
            || self
                .social
                .raid
                .safe_node_shares_bps
                .iter()
                .any(|share| *share == 0 || *share > 10_000)
            || self
                .social
                .attack
                .base_reward_credits
                .checked_mul(max_multiplier as u64)
                .is_none_or(|value| value > i64::MAX as u64)
            || self
                .social
                .shield_overflow_credits
                .checked_mul(max_multiplier as u64)
                .is_none_or(|value| value > i64::MAX as u64)
            || self
                .social
                .raid
                .base_pot_credits
                .checked_mul(max_multiplier as u64)
                .is_none_or(|value| value > i64::MAX as u64)
        {
            problems.push("social.json : paramètres hors limites".to_string());
        }
        let rarity_points = &self.progression.rarity_points;
        if self.progression.score_name.trim().is_empty()
            || self.progression.score_name.len() > 32
            || self.progression.upgrade_points == 0
            || self.progression.district_completion_points == 0
            || self.progression.set_completion_points == 0
            || self.progression.achievement_points == 0
            || self.progression.achievement_points > 10_000
            || self.progression.global_leaderboard_limit == 0
            || self.progression.global_leaderboard_limit > 100
            || [
                rarity_points.common,
                rarity_points.uncommon,
                rarity_points.rare,
                rarity_points.epic,
                rarity_points.legendary,
            ]
            .iter()
            .any(|points| *points == 0 || *points > 10_000)
        {
            problems.push("progression.json : paramètres hors limites".to_string());
        }
        let curve = &self.progression.district_curve;
        if !curve.parameters_are_sane() {
            problems.push("progression.districtCurve : paramètres hors limites".to_string());
        }

        let mut days = BTreeSet::new();
        if self.daily.cycle.is_empty() {
            problems.push("daily.cycle est vide".to_string());
        }
        for d in &self.daily.cycle {
            if d.day == 0 {
                problems.push("daily.cycle : day doit être >= 1".to_string());
            }
            if !days.insert(d.day) {
                problems.push(format!("daily.cycle : jour {} en double", d.day));
            }
            if d.spins > i32::MAX as u32 || d.credits > i64::MAX as u64 {
                problems.push(format!(
                    "daily.cycle : récompense jour {} hors stockage",
                    d.day
                ));
            }
        }
        let mut achievement_ids = BTreeSet::new();
        for achievement in &self.achievements {
            if !achievement_ids.insert(achievement.achievement_id.as_str())
                || achievement.achievement_id.trim().is_empty()
                || achievement.achievement_id.len() > 64
                || achievement.name.trim().is_empty()
                || achievement.name.len() > 64
                || achievement.description.trim().is_empty()
                || achievement.description.len() > 160
                || achievement.action.trim().is_empty()
                || achievement.action.len() > 48
                || !achievement
                    .action
                    .chars()
                    .all(|character| character.is_ascii_lowercase() || character == '_')
                || achievement.target == 0
                || achievement.target > i64::MAX as u64
                || achievement
                    .reward
                    .chest
                    .as_deref()
                    .is_some_and(|id| !self.chests.iter().any(|chest| chest.chest_id == id))
                || !reward_fits_storage(&achievement.reward)
            {
                problems.push(format!(
                    "achievement {} : définition invalide",
                    achievement.achievement_id
                ));
            }
        }
        let mut entitlement_ids = BTreeSet::new();
        let mut total_daily_spin_bonus = 0u32;
        for entitlement in &self.entitlements {
            total_daily_spin_bonus =
                total_daily_spin_bonus.saturating_add(entitlement.perks.daily_spin_bonus);
            if !entitlement_ids.insert(entitlement.entitlement_id.as_str())
                || entitlement.entitlement_id.trim().is_empty()
                || entitlement.entitlement_id.len() > 64
                || entitlement.name.trim().is_empty()
                || entitlement.name.len() > 64
                || entitlement.collection_address.trim().is_empty()
                || entitlement.collection_address.len() > 96
                || entitlement.verification_ttl_ms < 300_000
                || entitlement.verification_ttl_ms > 604_800_000
                || entitlement.perks.daily_spin_bonus > 1_000
                || entitlement
                    .perks
                    .badge_id
                    .as_deref()
                    .is_some_and(|badge| badge.trim().is_empty() || badge.len() > 32)
            {
                problems.push(format!(
                    "entitlement {} : définition invalide",
                    entitlement.entitlement_id
                ));
            }
        }
        if total_daily_spin_bonus > 2_000 {
            problems.push("entitlements : bonus daily cumulé trop élevé".to_string());
        }
        let mut bonus_outcome_ids = BTreeSet::new();
        let bonus_total_weight: u64 = self
            .daily
            .bonus
            .outcomes
            .iter()
            .map(|outcome| u64::from(outcome.weight))
            .sum();
        if self.daily.bonus.bonus_id.trim().is_empty()
            || self.daily.bonus.name.trim().is_empty()
            || self.daily.bonus.outcomes.is_empty()
            || bonus_total_weight == 0
            || bonus_total_weight > u64::from(u32::MAX)
        {
            problems.push("daily.bonus : identité/outcomes/poids invalides".to_string());
        }
        for outcome in &self.daily.bonus.outcomes {
            if outcome.outcome_id.trim().is_empty()
                || outcome.name.trim().is_empty()
                || outcome.weight == 0
                || !bonus_outcome_ids.insert(outcome.outcome_id.as_str())
                || !reward_fits_storage(&outcome.reward)
            {
                problems.push(format!(
                    "daily.bonus outcome invalide : {}",
                    outcome.outcome_id
                ));
            }
        }
        let mut mission_ids = BTreeSet::new();
        for m in &self.daily.missions {
            if m.target == 0 || !mission_ids.insert(&m.mission_id) {
                problems.push(format!("mission invalide ou en double : {}", m.mission_id));
            }
            if m.target > i64::MAX as u64 || !reward_fits_storage(&m.reward) {
                problems.push(format!(
                    "mission {} : cible/récompense hors stockage",
                    m.mission_id
                ));
            }
        }

        let mut district_ids = BTreeSet::new();
        if self.districts.is_empty() {
            problems.push("aucun district trouvé dans config/districts/".to_string());
        }
        for d in &self.districts {
            if !district_ids.insert(d.id) {
                problems.push(format!("districts : id {} en double", d.id));
            }
            if d.elements.is_empty() {
                problems.push(format!("district {} : éléments vides", d.id));
            }
            if d.id == 1 {
                if d.unlock_requirements.is_some() {
                    problems.push("district 1 ne doit pas avoir de prérequis".to_string());
                }
            } else if d
                .unlock_requirements
                .as_ref()
                .map(|requirements| requirements.completed_district_id)
                != Some(d.id - 1)
            {
                problems.push(format!(
                    "district {} doit exiger la complétion du district {}",
                    d.id,
                    d.id - 1
                ));
            }
            let mut elem_ids = BTreeSet::new();
            for e in &d.elements {
                if !elem_ids.insert(e.id) {
                    problems.push(format!("district {} : élément id {} en double", d.id, e.id));
                }
                if e.id > i32::MAX as u32 {
                    problems.push(format!(
                        "district {} : élément id {} hors INTEGER",
                        d.id, e.id
                    ));
                }
                let mut levels = BTreeSet::new();
                for l in &e.levels {
                    if !levels.insert(l.level) {
                        problems.push(format!(
                            "district {} / élément {} : niveau {} en double",
                            d.id, e.id, l.level
                        ));
                    }
                    if l.cost > i64::MAX as u64 {
                        problems.push(format!(
                            "district {} / élément {} : coût hors BIGINT",
                            d.id, e.id
                        ));
                    }
                    if l.level > i32::MAX as u32 {
                        problems.push(format!(
                            "district {} / élément {} : niveau hors INTEGER",
                            d.id, e.id
                        ));
                    }
                }
                let max = e.levels.iter().map(|l| l.level).max().unwrap_or(0);
                if !(0..=max).all(|level| e.levels.iter().any(|l| l.level == level)) {
                    problems.push(format!(
                        "district {} / élément {} : niveaux non contigus",
                        d.id, e.id
                    ));
                }
            }
            if d.completion_reward.as_ref().is_some_and(|reward| {
                reward.spins > i32::MAX as u32 || reward.credits > i64::MAX as u64
            }) {
                problems.push(format!("district {} : récompense hors stockage", d.id));
            }
        }
        if !(1..=self.districts.len() as u32).all(|id| district_ids.contains(&id)) {
            problems.push("districts : ids attendus contigus à partir de 1".to_string());
        }

        // Enveloppe de progression : un district ajouté par config ne doit pas
        // pouvoir casser l'équilibrage sans que le boot le refuse.
        if curve.parameters_are_sane() {
            let mut previous_total: u128 = 0;
            for id in 1..=self.districts.len() as u32 {
                let Some(district) = self.districts.iter().find(|d| d.id == id) else {
                    continue;
                };
                let mut total: u128 = 0;
                for element in &district.elements {
                    let mut levels: Vec<&DistrictLevel> = element.levels.iter().collect();
                    levels.sort_by_key(|level| level.level);
                    let mut previous_cost: u64 = 0;
                    for level in levels {
                        total += level.cost as u128;
                        if previous_cost > 0 && level.cost > 0 {
                            let growth = level.cost as f64 / previous_cost as f64;
                            if growth < curve.level_cost_growth_min
                                || growth > curve.level_cost_growth_max
                            {
                                problems.push(format!(
                                    "district {} / élément {} niveau {} : croissance {:.2} hors enveloppe [{:.2}, {:.2}]",
                                    district.id,
                                    element.id,
                                    level.level,
                                    growth,
                                    curve.level_cost_growth_min,
                                    curve.level_cost_growth_max
                                ));
                            }
                        }
                        if level.cost > 0 {
                            previous_cost = level.cost;
                        }
                    }
                }
                if total > i64::MAX as u128 {
                    problems.push(format!(
                        "district {} : coût total {} hors BIGINT",
                        district.id, total
                    ));
                }
                let deviation = curve.cost_deviation(id, total);
                if deviation > curve.district_cost_tolerance {
                    problems.push(format!(
                        "district {} : coût total {} hors enveloppe, écart {:.1} % pour une tolérance de {:.1} %",
                        district.id,
                        total,
                        deviation * 100.0,
                        curve.district_cost_tolerance * 100.0
                    ));
                }
                if total <= previous_total {
                    problems.push(format!(
                        "district {} : coût total {} doit dépasser celui du district précédent ({})",
                        district.id, total, previous_total
                    ));
                }
                previous_total = total;
            }
        }

        let card_ids: BTreeSet<&str> = self.cards.iter().map(|c| c.card_id.as_str()).collect();
        if card_ids.len() != self.cards.len() {
            problems.push("cards : cardId en double".to_string());
        }
        let set_ids: BTreeSet<&str> = self.sets.iter().map(|s| s.set_id.as_str()).collect();
        if set_ids.len() != self.sets.len() {
            problems.push("sets : setId en double".to_string());
        }
        for card in &self.cards {
            if !set_ids.contains(card.set_id.as_str()) || card.drop_weight == 0 {
                problems.push(format!("carte {} : set inconnu ou poids nul", card.card_id));
            }
        }
        for set in &self.sets {
            if set.completion_spins > i32::MAX as u32 {
                problems.push(format!(
                    "set {} : récompense spins hors INTEGER",
                    set.set_id
                ));
            }
            for card in &set.cards {
                if !card_ids.contains(card.as_str()) {
                    problems.push(format!("set {} : carte inconnue {}", set.set_id, card));
                }
            }
        }
        let chest_ids: BTreeSet<&str> = self.chests.iter().map(|c| c.chest_id.as_str()).collect();
        if chest_ids.len() != self.chests.len() {
            problems.push("chests : chestId en double".to_string());
        }
        for outcome in self
            .spin_table
            .outcomes
            .iter()
            .filter(|outcome| outcome.outcome_type == OutcomeType::Chest)
        {
            if outcome
                .reward_id
                .as_deref()
                .is_none_or(|id| !chest_ids.contains(id))
            {
                problems.push(format!(
                    "spin_table.{} : rewardId de coffre inconnu",
                    outcome.id
                ));
            }
        }
        for chest in &self.chests {
            if chest.cards_per_open == 0
                || chest.loot_table.iter().map(|l| l.weight).sum::<u32>() == 0
            {
                problems.push(format!("chest {} : loot table invalide", chest.chest_id));
            }
            if chest.price_credits > i64::MAX as u64 {
                problems.push(format!("chest {} : prix hors BIGINT", chest.chest_id));
            }
            for loot in &chest.loot_table {
                if !self.cards.iter().any(|card| card.rarity == loot.rarity) {
                    problems.push(format!(
                        "chest {} : aucune carte pour la rareté {:?}",
                        chest.chest_id, loot.rarity
                    ));
                }
            }
        }
        for daily in &self.daily.cycle {
            if daily
                .chest
                .as_deref()
                .is_some_and(|id| !chest_ids.contains(id))
            {
                problems.push(format!("daily jour {} : coffre inconnu", daily.day));
            }
        }
        for mission in &self.daily.missions {
            if mission
                .reward
                .chest
                .as_deref()
                .is_some_and(|id| !chest_ids.contains(id))
            {
                problems.push(format!("mission {} : coffre inconnu", mission.mission_id));
            }
        }
        for outcome in &self.daily.bonus.outcomes {
            if outcome
                .reward
                .chest
                .as_deref()
                .is_some_and(|id| !chest_ids.contains(id))
            {
                problems.push(format!(
                    "daily bonus {} : coffre inconnu",
                    outcome.outcome_id
                ));
            }
        }
        for district in &self.districts {
            if district
                .completion_reward
                .as_ref()
                .and_then(|r| r.chest.as_deref())
                .is_some_and(|id| !chest_ids.contains(id))
            {
                problems.push(format!(
                    "district {} : coffre de récompense inconnu",
                    district.id
                ));
            }
        }
        let event_ids: BTreeSet<&str> = self.events.iter().map(|e| e.event_id.as_str()).collect();
        if event_ids.len() != self.events.len() {
            problems.push("events : eventId en double".to_string());
        }
        for event in &self.events {
            if event.starts_at_ms >= event.ends_at_ms {
                problems.push(format!("event {} : fenêtre invalide", event.event_id));
            }
            if event
                .point_sources
                .iter()
                .any(|source| source.points > i64::MAX as u64)
            {
                problems.push(format!("event {} : points hors BIGINT", event.event_id));
            }
            if event.leaderboard.cohort_size == 0
                || event.leaderboard.cohort_size > 500
                || event.leaderboard.display_limit == 0
                || event.leaderboard.display_limit > 100
            {
                problems.push(format!("event {} : leaderboard invalide", event.event_id));
            }
            let mut previous_milestone = 0u64;
            for milestone in &event.milestones {
                if milestone.points <= previous_milestone
                    || milestone.points > i64::MAX as u64
                    || !reward_fits_storage(&milestone.reward)
                {
                    problems.push(format!("event {} : milestone invalide", event.event_id));
                }
                previous_milestone = milestone.points;
            }
            if let Some(team) = &event.team {
                if team.name.trim().is_empty()
                    || team.min_contribution_points == 0
                    || team.min_contribution_points > i64::MAX as u64
                    || team.milestones.is_empty()
                {
                    problems.push(format!("event {} : équipe invalide", event.event_id));
                }
                let mut previous_team_milestone = 0u64;
                for milestone in &team.milestones {
                    if milestone.points <= previous_team_milestone
                        || milestone.points > i64::MAX as u64
                        || milestone
                            .reward
                            .chest
                            .as_deref()
                            .is_some_and(|id| !chest_ids.contains(id))
                        || !reward_fits_storage(&milestone.reward)
                    {
                        problems.push(format!(
                            "event {} : milestone équipe invalide",
                            event.event_id
                        ));
                    }
                    previous_team_milestone = milestone.points;
                }
            }
            let mut previous_max_rank = 0u32;
            for tier in &event.reward_tiers {
                if tier.min_rank == 0
                    || tier.min_rank > tier.max_rank
                    || tier.min_rank != previous_max_rank.saturating_add(1)
                    || tier.max_rank > event.leaderboard.cohort_size
                    || tier
                        .reward
                        .chest
                        .as_deref()
                        .is_some_and(|id| !chest_ids.contains(id))
                    || !reward_fits_storage(&tier.reward)
                {
                    problems.push(format!("event {} : palier invalide", event.event_id));
                }
                previous_max_rank = tier.max_rank;
            }
            if previous_max_rank != event.leaderboard.cohort_size {
                problems.push(format!(
                    "event {} : paliers incomplets jusqu'à la taille de cohorte",
                    event.event_id
                ));
            }
        }
        let season_ids: BTreeSet<&str> =
            self.seasons.iter().map(|s| s.season_id.as_str()).collect();
        if season_ids.len() != self.seasons.len() {
            problems.push("seasons : seasonId en double".to_string());
        }
        for season in &self.seasons {
            if season.starts_at_ms >= season.ends_at_ms || season.tiers.is_empty() {
                problems.push(format!(
                    "season {} : fenêtre/paliers invalides",
                    season.season_id
                ));
            }
            if season.tiers.iter().any(|tier| {
                tier.points > i64::MAX as u64
                    || !reward_fits_storage(&tier.free_reward)
                    || tier
                        .premium_reward
                        .as_ref()
                        .is_some_and(|reward| !reward_fits_storage(reward))
            }) {
                problems.push(format!(
                    "season {} : palier hors stockage",
                    season.season_id
                ));
            }
        }
        if self.reward_pool.settlement_enabled && !self.reward_pool.enabled {
            problems.push("rewardPool.settlementEnabled exige rewardPool.enabled".to_string());
        }
        if self.reward_pool.enabled && self.reward_pool.pools.is_empty() {
            problems.push("rewardPool activé sans pool".to_string());
        }
        let pool_ids: BTreeSet<&str> = self
            .reward_pool
            .pools
            .iter()
            .map(|pool| pool.pool_id.as_str())
            .collect();
        if pool_ids.len() != self.reward_pool.pools.len() {
            problems.push("rewardPool : poolId en double".to_string());
        }
        for pool in &self.reward_pool.pools {
            let valid_identity = !pool.pool_id.trim().is_empty()
                && pool.pool_id.len() <= 64
                && !pool.token_mint.trim().is_empty()
                && pool.token_mint.len() <= 128;
            let valid_economy = pool.starts_at_ms < pool.ends_at_ms
                && pool.budget_u64 > 0
                && pool.budget_u64 <= i64::MAX as u64
                && pool.min_claim_u64 > 0
                && pool.min_claim_u64 <= pool.budget_u64
                && !pool.rules.is_empty();
            if !valid_identity || !valid_economy {
                problems.push(format!("rewardPool {} : définition invalide", pool.pool_id));
            }
            let mut rule_keys = BTreeSet::new();
            for rule in &pool.rules {
                let source_exists = match rule.source.as_str() {
                    "district_complete" => {
                        rule.source_id.parse::<u32>().ok().is_some_and(|id| {
                            self.districts.iter().any(|district| district.id == id)
                        })
                    }
                    "achievement_claim" => self
                        .achievements
                        .iter()
                        .any(|achievement| achievement.achievement_id == rule.source_id),
                    _ => false,
                };
                if !source_exists
                    || rule.source_id.is_empty()
                    || rule.source_id.len() > 96
                    || rule.amount_u64 == 0
                    || rule.amount_u64 > pool.budget_u64
                    || !rule_keys.insert((rule.source.as_str(), rule.source_id.as_str()))
                {
                    problems.push(format!("rewardPool {} : règle invalide", pool.pool_id));
                }
            }
        }

        let offer_ids: BTreeSet<&str> = self.offers.iter().map(|o| o.offer_id.as_str()).collect();
        if offer_ids.len() != self.offers.len() {
            problems.push("offers : offerId en double".to_string());
        }
        for offer in &self.offers {
            if offer.starts_at_ms >= offer.ends_at_ms
                || offer.max_per_player == 0
                || !matches!(
                    offer.kind.as_str(),
                    "starter" | "spin_pack" | "progression" | "event" | "returning" | "season_pass"
                )
                || offer
                    .eligibility
                    .max_account_age_ms
                    .is_some_and(|value| value < 60_000 || value > i64::MAX as u64)
                || offer
                    .eligibility
                    .min_inactivity_ms
                    .is_some_and(|value| value < 60_000 || value > i64::MAX as u64)
                || offer
                    .eligibility
                    .max_spins
                    .is_some_and(|value| value > i32::MAX as u32)
                || offer
                    .eligibility
                    .min_district_index
                    .zip(offer.eligibility.max_district_index)
                    .is_some_and(|(minimum, maximum)| minimum > maximum)
                || offer
                    .eligibility
                    .requires_event_id
                    .as_deref()
                    .is_some_and(|id| !event_ids.contains(id))
            {
                problems.push(format!(
                    "offer {} : type/fenêtre/limite/éligibilité invalide",
                    offer.offer_id
                ));
            }
            for content in &offer.contents {
                if content.amount > i64::MAX as u64 {
                    problems.push(format!("offer {} : montant hors BIGINT", offer.offer_id));
                }
                match content.content_type.as_str() {
                    "spins" | "credits" => {}
                    "chest"
                        if content
                            .id
                            .as_deref()
                            .is_some_and(|id| self.chests.iter().any(|c| c.chest_id == id)) => {}
                    "season_premium"
                        if content
                            .id
                            .as_deref()
                            .is_some_and(|id| self.seasons.iter().any(|s| s.season_id == id)) => {}
                    _ => problems.push(format!("offer {} : contenu invalide", offer.offer_id)),
                }
            }
        }

        if !problems.is_empty() {
            bail!("config invalide :\n - {}", problems.join("\n - "));
        }
        Ok(())
    }

    /// Payload servi par GET /config.
    pub fn payload(&self) -> Value {
        json!({
            "economy": self.economy,
            "spinTable": self.spin_table,
            "social": self.social,
            "progression": self.progression,
            "rewardPool": self.reward_pool,
            "daily": self.daily,
            "achievements": self.achievements,
            "entitlements": self.entitlements,
            "districts": self.districts,
            "cards": self.cards,
            "sets": self.sets,
            "chests": self.chests,
            "events": self.events,
            "offers": self.offers,
            "seasons": self.seasons,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bundled_config_is_valid() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../config");
        let cfg = RemoteConfig::load(&path).expect("la config livrée doit rester valide");
        assert!(!cfg.spin_table.outcomes.is_empty());
        assert!(!cfg.districts.is_empty());
        assert_eq!(cfg.economy.spin_multipliers.first(), Some(&1));
        assert_eq!(cfg.economy.spin_multipliers.last(), Some(&100_000));
    }

    /// L'enveloppe doit rejeter un district ajouté par config qui dérive de la
    /// courbe, sinon ajouter du contenu casse l'équilibrage en silence.
    #[test]
    fn district_curve_envelope_rejects_off_curve_content() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../config");
        let mut cfg = RemoteConfig::load(&path).expect("la config livrée doit rester valide");
        let curve = &cfg.progression.district_curve;

        // La config livrée doit rester dans son propre couloir.
        for id in 1..=cfg.districts.len() as u32 {
            let district = cfg
                .districts
                .iter()
                .find(|d| d.id == id)
                .expect("districts contigus");
            let total: u128 = district
                .elements
                .iter()
                .flat_map(|element| element.levels.iter())
                .map(|level| level.cost as u128)
                .sum();
            let deviation = curve.cost_deviation(id, total);
            assert!(
                deviation <= curve.district_cost_tolerance,
                "district {} hors enveloppe : écart {:.3} pour une tolérance de {:.3}",
                id,
                deviation,
                curve.district_cost_tolerance
            );
        }

        // La fenêtre de spins doit s'élargir avec l'index, pas rester figée.
        let (first_min, first_max) = curve.expected_spins_window(1);
        let (second_min, second_max) = curve.expected_spins_window(2);
        assert!(second_min > first_min && second_max > first_max);

        // Un dernier district dix fois trop cher doit faire échouer la validation.
        let last = cfg.districts.len() - 1;
        for element in &mut cfg.districts[last].elements {
            for level in &mut element.levels {
                level.cost = level.cost.saturating_mul(10);
            }
        }
        let problems = cfg
            .validate()
            .expect_err("un district hors courbe doit échouer");
        assert!(
            problems.to_string().contains("hors enveloppe"),
            "message inattendu : {}",
            problems
        );
    }

    /// La croissance par niveau n'est vérifiée qu'ici (la gate PowerShell ne la
    /// rejuge pas), donc elle a besoin de sa propre preuve.
    #[test]
    fn district_curve_rejects_flat_level_progression() {
        let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../config");
        let mut cfg = RemoteConfig::load(&path).expect("la config livrée doit rester valide");

        // Aplatir un élément : tous les niveaux payants au même prix. Le coût
        // total reste plausible mais la marche entre niveaux disparaît.
        let element = &mut cfg.districts[0].elements[0];
        let reference = element
            .levels
            .iter()
            .filter(|level| level.cost > 0)
            .map(|level| level.cost)
            .max()
            .expect("un niveau payant");
        for level in &mut element.levels {
            if level.cost > 0 {
                level.cost = reference;
            }
        }

        let problems = cfg
            .validate()
            .expect_err("une progression plate doit échouer");
        assert!(
            problems.to_string().contains("croissance"),
            "message inattendu : {}",
            problems
        );
    }
}
