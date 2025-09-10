# Copilot Instructions for TopInfectors

## Repository Overview

This repository contains the **TopInfectors** SourcePawn plugin for SourceMod, designed for zombie infection-based Source engine game servers. The plugin tracks and displays the top-performing players who successfully infect humans in zombie modes, providing visual feedback, rewards, and leaderboard functionality.

### Key Features
- Real-time tracking of player infection statistics
- HUD display with customizable positioning and colors
- Reward system (grenades for top performers)
- 3D skull model display for top infectors
- Multi-language support via translations
- Native API for integration with other plugins
- Client preferences system (skull visibility toggle)

## Technical Stack

- **Language**: SourcePawn
- **Platform**: SourceMod 1.11+ (configured for 1.11.0-git6934)
- **Build System**: SourceKnight 0.2
- **Target Games**: Source Engine games with zombie infection modes
- **Dependencies**: Multiple SourceMod extensions and plugins

## Project Structure

```
/
├── .github/
│   ├── workflows/ci.yml          # CI/CD pipeline
│   └── copilot-instructions.md   # This file
├── addons/sourcemod/
│   ├── scripting/
│   │   ├── TopInfectors.sp       # Main plugin source
│   │   └── include/
│   │       └── TopInfectors.inc  # Native API definitions
│   └── translations/
│       └── topinfectors.phrases.txt  # Multi-language strings
├── materials/models/unloze/skull/ # Texture files for skull model
├── models/unloze/                # 3D skull model files
├── sound/topinfectors/           # Audio assets
└── sourceknight.yaml            # Build configuration & dependencies
```

## Build System

This project uses **SourceKnight** for dependency management and building, not direct spcomp compilation.

### Building the Plugin
```bash
# Using SourceKnight directly (if available)
sourceknight build

# Via GitHub Actions (recommended)
# Push to main/master branch or create PR - CI will build automatically
```

### Dependencies (Auto-managed via SourceKnight)
- **sourcemod**: Core SourceMod framework (1.11.0-git6934)
- **multicolors**: Enhanced chat color formatting
- **zombiereloaded**: Zombie infection game mode framework
- **loghelper**: Logging utilities
- **utilshelper**: Common utility functions  
- **smlib**: Extended SourceMod library functions
- **dynamicchannels**: Dynamic HUD channel management (optional)

### Key Files to Understand
1. **sourceknight.yaml**: Build configuration, dependencies, and targets
2. **TopInfectors.sp**: Main plugin logic (746 lines)
3. **TopInfectors.inc**: Native function definitions for other plugins
4. **.github/workflows/ci.yml**: Automated build, test, and release pipeline

## Development Guidelines

### Code Style Standards
```sourcepawn
// Use tabs for indentation (4 spaces)
// camelCase for local variables and parameters
int playerCount = 0;
char playerName[64];

// PascalCase for functions and global variables  
void UpdatePlayerStats()
bool IsPlayerValid()

// Prefix global variables with "g_"
int g_iInfectCount[MAXPLAYERS + 1];
ConVar g_cvHat;

// Required pragmas
#pragma semicolon 1
#pragma newdecls required
```

### Memory Management Best Practices
```sourcepawn
// Use delete directly without null checks
delete g_hUpdateTimer;  // Good
g_hUpdateTimer = null;

// NEVER use .Clear() on StringMap/ArrayList - creates memory leaks
delete playerMap;       // Good
playerMap = new StringMap();

// Use methodmaps for data structures
StringMap playerData = new StringMap();
ArrayList playerList = new ArrayList();
```

### Plugin Structure Pattern
```sourcepawn
// Standard plugin lifecycle
public void OnPluginStart()
{
    // Initialize ConVars, commands, hooks
    // Load translations
    // Create data structures
}

public void OnPluginEnd()  
{
    // Clean up handles and resources
    // Only implement if cleanup is necessary
}

// Use proper event hooks
public Action ZR_OnClientInfect(int &client, int &attacker, bool &motherInfect, bool &respawnOverride, bool &respawn)
{
    // Game-specific event handling
    return Plugin_Continue;
}
```

## Key Components

### 1. Statistics Tracking
- **g_iInfectCount[]**: Per-client infection counters
- **g_iSortedList[][]**: Sorted leaderboard data  
- **UpdateInfectorsList()**: Timer-based leaderboard updates

### 2. Visual Elements
- **HUD Display**: Customizable position/color via ConVars
- **3D Skull Models**: Spawned on top infectors' heads
- **Chat Messages**: Multi-language notifications

### 3. Reward System
- **SetPerks()**: Grants grenades to top performers
- Configurable grenade types (HE, Smoke) via ConVars

### 4. Native API
```sourcepawn
// Deprecated - use TopInfectors_GetClientRank() instead
native int IsTopInfector(int client);

// Current API
native int TopInfectors_GetClientRank(int client);
// Returns: -1 if not ranked, otherwise rank position
```

## Configuration

### ConVars (Runtime Configuration)
- `sm_topinfectors_hat`: Enable/disable skull models
- `sm_topinfectors_amount`: Number of top players to track
- `sm_topinfectors_print_position`: HUD display coordinates
- `sm_topinfectors_print_color`: RGB color values
- `sm_topinfectors_henades`: HE grenade rewards
- `sm_topinfectors_smokenades`: Smoke grenade rewards

### Translation Keys
Located in `addons/sourcemod/translations/topinfectors.phrases.txt`:
- Chat prefixes, menu titles, status messages
- Supports multiple languages (currently English)

## Common Development Tasks

### Adding New Features
1. **New ConVar**: Add to `OnPluginStart()`, handle in appropriate functions
2. **New Translation**: Add key to `topinfectors.phrases.txt`  
3. **New Native**: Add to `TopInfectors.inc`, implement in main plugin
4. **New Game Support**: Add game-specific logic with proper hooks

### Modifying Display Logic
- **HUD Updates**: Modify `UpdateInfectorsList()` and display logic
- **Chat Messages**: Use `CPrintToChat()` with translation keys
- **Colors**: Respect `g_iPrintColor[]` settings

### Asset Management
- **Models**: Place in `models/` directory, update model cache in plugin
- **Materials**: Place in `materials/` directory, ensure proper VTF/VMT pairs
- **Sounds**: Place in `sound/topinfectors/`, update precache logic

## Testing & Validation

### Build Testing
```bash
# CI automatically builds on push/PR
# Check GitHub Actions for build status
# Download artifacts from successful builds
```

### Runtime Testing
1. **Server Setup**: Install on SourceMod-enabled game server
2. **Game Mode**: Requires zombie infection game mode (ZombieReloaded)
3. **Test Scenarios**:
   - Player infections and stat tracking
   - HUD display positioning/colors
   - Reward distribution
   - Native function calls from other plugins

### Common Issues
- **Missing Dependencies**: Check sourceknight.yaml for all required includes
- **Model/Material Loading**: Ensure proper file paths and precaching
- **Memory Leaks**: Validate all Handle cleanup and avoid .Clear() usage
- **Translation Missing**: Check phrase keys match exactly

## Release Process

### Versioning
- **Location**: `TopInfectors.inc` - `TopInfectors_V_MAJOR/MINOR/PATCH`
- **Format**: Semantic versioning (1.5.5 current)
- **Git Tags**: Create tags for releases, CI auto-builds and releases

### Package Contents
```
TopInfectors-{version}.tar.gz
├── addons/sourcemod/
│   ├── plugins/TopInfectors.smx
│   └── translations/topinfectors.phrases.txt
├── materials/models/unloze/skull/
├── models/unloze/
└── sound/topinfectors/
```

### CI/CD Pipeline
1. **Build**: Compiles plugin via SourceKnight action
2. **Package**: Creates release archive with all assets
3. **Release**: Auto-publishes to GitHub releases for tags/master

## Integration Points

### Other Plugins
- **ZombieReloaded**: Core dependency for infection events
- **DynamicChannels**: Optional for improved HUD channel management  
- **Nemesis**: Optional integration for special zombie types

### Game Events
- **player_hurt**: Potential for damage tracking
- **round_start/end**: Reset statistics, distribute rewards
- **player_spawn**: Skull model management

## Performance Considerations

- **Timer Frequency**: `UpdateInfectorsList()` runs every 1.0 seconds
- **HUD Updates**: Only update when data changes to reduce network traffic
- **Model Management**: Efficiently handle skull entity creation/cleanup
- **Memory Usage**: Proper Handle cleanup prevents server memory leaks

## Debugging Tips

### Common Debug Scenarios
1. **Stats Not Updating**: Check ZR event hooks and client validation
2. **HUD Not Displaying**: Verify position values and color settings
3. **Models Not Appearing**: Check model precaching and entity management
4. **Rewards Not Working**: Validate grenade giving logic and permissions

### Logging
- Use `LogHelper` functions for consistent logging format
- Add debug prints for development builds
- Monitor SourceMod error logs for Handle leaks

## File Modification Guidelines

### High-Impact Files
- **TopInfectors.sp**: Main plugin logic - test thoroughly after changes
- **TopInfectors.inc**: API changes affect dependent plugins
- **sourceknight.yaml**: Dependency changes require full rebuild

### Safe Modifications
- **topinfectors.phrases.txt**: Translation updates (test with `sm_lang` changes)
- **README.md**: Documentation updates
- **ci.yml**: Build pipeline improvements (test in PR before merge)

This plugin is mature and stable - make minimal, focused changes and test thoroughly on a development server before deploying to production environments.