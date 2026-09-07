# R42 — provenance et prompts

Outil : génération d'images intégrée, pas de clé API ni de modèle local.
Référence utilisateur : `reference.png`. Conserver CyberSeeker comme nom produit.
Les quatre PNG retenus vivent dans `source/`; la conversion WebP qualité 96,
sans redimensionnement ni détourage par script, est assurée par
`tools/import_reference_art.gd`. Les versions intermédiaires à damier ont été
rejetées, corrigées avec le même outil, puis vérifiées RGBA/alpha.

## Cabinet — prompt initial

Create ONE production-ready transparent PNG game asset: the spectacular central cyberpunk SLOT MACHINE CABINET from the attached game's reference, isolated against true transparency. Treat the reference as exact ART DIRECTION: polished hand-painted cartoon mobile game illustration, bold coherent outlines, cobalt metal, deep navy shadows, electric cyan and vivid magenta LED edge trim, angular bevels, substantial sculpted dimensional hardware, NOT photorealistic and not sketchy. Front-on symmetrical cabinet, portrait aspect about 0.85 width to height. Fill most of canvas. Include the right lever with purple spherical handle. IMPORTANT empty interior: large rectangular reel opening at horizontal 17%-79%, vertical 18%-68% should be an empty very pale silver surface, with no symbols and no vertical dividers, to place interactive reels on top. Small dark empty horizontal header display centered at y9%, a small empty dark betting plaque at y74%, a large fabulous orange/gold beveled hexagonal button at y86% with EMPTY orange center. NO TEXT, no letters, NO NUMBERS, no logos, no symbols, NO HUD, NO CITY, no icons, no people, no floor, no cast shadow outside cabinet. This is a standalone cabinet sprite for a functioning slot machine. Maintain the reference craftsmanship, reflective edges and cyan-magenta underlighting. Preserve clean silhouette and alpha outside all cabinet parts.

### Dernier prompt — correction alpha retenue

EDIT ONLY BACKGROUND. Remove the fake white and grey checkerboard background outside the slot machine completely. Return this SAME cabinet artwork with REAL ALPHA TRANSPARENCY, actual RGBA cutout. White/silver inside the reel window must remain opaque. Preserve exact dimensions, composition and all cabinet pixels including right lever. Do not redesign. No checkerboard, no background color, no studio background. The checkerboard is currently baked into the RGB source and must be removed, not reproduced. Transparent background mandatory.

Source retenue : exec-8274b962-2d4a-4d16-9ece-b53ea91e4733.png, 1024×1536 RGBA.

## Ville — prompt final

Make a production game BACKGROUND plate only, portrait 2:3. Follow attached reference's exact painted cartoon cyberpunk art direction and palette. A rich dimensional neon city at night, looking down a narrow avenue between tall toy-like dark cobalt futuristic buildings, scattered tiny cyan windows and magenta signage, blue and violet atmospheric perspective. Foreground pavement reflective blue neon wet tiles. Central composition DARK and spacious for UI; deep near-black navy void behind top logo area and central machine, bright little city details mostly at sides and bottom. Crisp hand painted cartoon mobile game aesthetic with clean chunky bevels and outlines, not realism, not photographic, not noisy AI detail. NO SLOT MACHINE, NO TEXT, NO UI, NO PANELS, NO CHARACTERS, NO ICONS, NO LOGO, no symbols. Environment illustration only filling canvas, completely opaque.

Source : exec-b6cefef5-3b10-40bc-b733-7be4cb8a6115.png, 1024×1536 RGB.

## Atlas d'icônes — prompt initial

Create ONE game sprite ATLAS, transparent PNG square canvas, exact regular 3 COLUMNS x 4 ROWS grid, 12 distinct isolated icons. Each icon centered in its equal sized cell with generous padding, no touching neighboring cells, no grid lines, no background, no text or letters anywhere. Reproduce the attached reference's polished cartoon cyberpunk mobile game icon art: bold clean dark outlines, thick metallic dimensional bevels, saturated rich colors, very readable silhouettes, cyan and magenta lighting. Row1 left to right: 1 golden embossed crown coin, 2 electric blue armored shield with cyan lightning bolt, 3 glowing hot pink crosshair target in small black bevel tile. Row2: 4 purple blue futuristic treasure chest, 5 tilted cyan luminous battery with lightning bolt, 6 purple skull token coin. Row3: 7 purple-awning neon street shop, 8 a fan of three collectible cards with blue/purple robot face, 9 purple ribbon gift box. Row4: 10 blue planet globe, 11 golden trophy cup, 12 purple blue rocket. Exact twelve icons in this specified order, consistently scaled and professionally finished. Actual alpha transparency outside icons, no checkerboard drawn.

### Dernier prompt — correction alpha retenue

EDIT ONLY BACKGROUND. Remove the fake white and grey checkerboard background around ALL TWELVE ICONS completely. Return this SAME exact 3 columns by 4 rows atlas with REAL ALPHA TRANSPARENCY, actual RGBA cutout. Preserve the exact grid, canvas, icon positions, colors, lighting and all artwork. No redesign. No checkerboard painted or drawn in the output. No background color. Preserve transparent empty spaces between icons. Transparent background mandatory.

Source retenue : exec-9849876f-ff87-49a0-bc92-ca408d5bf3d1.png, 1244×1264 RGBA.
Les gouttières ne sont pas parfaitement régulières ; régions mesurées dans
`NeonSkin.ICON_RECTS`, sans modifier l'image source.

## Logo — prompt final

One standalone transparent PNG GAME LOGO, landscape 3:2. Match attached reference PUNK CITY logo art direction extremely closely but text MUST be exactly two lines: CYBER on top, SEEKER on bottom. Big expressive italic graffiti brush lettering with sculpted extruded deep navy and purple thick outline, white pearlescent pink-edged top word, luminous cyan turquoise blue gradient bottom word. Small asymmetrical neon pink crown hovering above left CYBER, magenta paint splatters around outline, a dark irregular shield shape behind letters. Slight counterclockwise dynamic tilt. Include a tiny dark blue beveled subtitle plaque under logo reading exactly BUILD • SPIN • CONQUER. No other words, no background, no city, no UI, no figures. Perfectly readable polished cartoon mobile game title typography, bold shapes and gorgeous beveled highlights. Exact lettering CYBER SEEKER, no extra letters. Transparent alpha outside emblem.

Source : exec-c90c18a6-4505-4d43-a35e-b7d977d14214.png, 1536×1024 RGBA.

## Atlas village — tentative non produite, à reprendre

Create one RGBA transparent PNG game BUILDING ATLAS, landscape 3:2 canvas, exact 5 equal COLUMNS and 2 equal ROWS. Ten isolated isometric cartoon cyberpunk village buildings with small oval blue paving bases. Match the bottom village buildings in the attached reference very closely: polished hand-painted collectible toy-like 2.5D, chunky cobalt metallic architecture, cyan windows, violet and magenta neon lights, crisp outlines and beautiful dimensional bevels. TOP ROW fully built, five buildings from left to right: 1 neon corner BAR tower with pink signage, 2 machinery workshop with circular glowing turbine, 3 largest royal central headquarters skyscraper with a blue glowing crown on top, 4 gold-purple casino with luminous roulette wheel sign, 5 communications power station with blue satellite dish. BOTTOM ROW the SAME FIVE buildings in same column order but early construction stage, about one third height, smaller basic foundation and one functioning blue lit storey, visibly recognizable identity. Each sprite fits entirely in its own equal cell, generous transparent padding no overlaps and no labels, no numbers or upgrade controls, NO BACKGROUND OR CITY. Actual transparent alpha outside each building. Do NOT paint a checkerboard. Colors saturated violet blue cyan, not muted brown grey. Real game sprite atlas only, no screenshot/UI.

Résultat : HTTP 429, `usage_limit_reached`. Aucun nouveau bâtiment produit,
aucun détourage ou génération alternative non autorisée pour contourner cette limite.
