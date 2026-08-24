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
    "cards.json",
    "chests.json",
    "daily.json",
    "economy.json",
    "events.json",
    "offers.json",
    "progression.json",
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

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgressionConfig {
    pub score_name: String,
    pub upgrade_points: u32,
    pub district_completion_points: u32,
    pub set_completion_points: u32,
    pub rarity_points: RarityPointsConfig,
    pub global_leaderboard_limit: u32,
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
    pub daily: DailyConfig,
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
        // 1) Inventaire : 8 fichiers de premier niveau + districts/*.json (triés).
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
        let daily: DailyConfig = serde_json::from_slice(get_entry(&entries, "daily.json")?)
            .context("daily.json invalide")?;
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
            daily,
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
            "daily": self.daily,
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
}
