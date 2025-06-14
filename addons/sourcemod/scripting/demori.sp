#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#tryinclude <updater>
#define REQUIRE_PLUGIN

#define PLUGIN_VERSION "1.5"
#define UPDATE_URL "https://raw.githubusercontent.com/issari-tf/Demorai/main/updater.txt"

#define HALF_ZATOICHI   357

#define PARTICLE_GHOST "ghost_appearation"
#define DASH_SOUND     "Halloween.spell_teleport"

// Dash constants
#define MAX_DASH_DISTANCE 384.0
#define DASH_DAMAGE 200
#define MAX_DASHES 3

public Plugin myinfo = {
  name        = "Demori",
  author      = "Koto, Aidan Sanders",
  description = "Half Demoman, Half Samurai, All Trouble.",
  version     =  PLUGIN_VERSION,
  url         = "https://github.com/issari-tf/Demorai"
};

// ConVars
ConVar gCV_Enable;
ConVar gCV_AutoUpdate;
ConVar gCV_DashDistance;

// Player Data
int g_iPlayerDashes[MAXPLAYERS + 1];
int g_iPlayerLastButtons[MAXPLAYERS + 1];
bool g_bPlayerHasEyes[MAXPLAYERS + 1];

public void OnPluginStart()
{
  CreateConVar("demori_version", PLUGIN_VERSION, "Demori Version", 
    FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_UNLOGGED | FCVAR_DONTRECORD | FCVAR_REPLICATED | FCVAR_NOTIFY);

  gCV_Enable = CreateConVar("demori_enable", "1", "Enable the plugin? 1 = Enable, 0 = Disable", FCVAR_NOTIFY);
  gCV_AutoUpdate = CreateConVar("demori_auto_update", "1", "automatically update when newest versions are available. Does nothing if updater plugin isn't used.", FCVAR_NONE, true, 0.0, true, 1.0);
  gCV_DashDistance = CreateConVar("demori_dash_distance", "384.0", "Maximum dash distance in hammer units", FCVAR_NONE, true, 64.0, true, 2048.0);

  HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_Pre);
  HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);

  // Late load support
  for (int i = 1; i <= MaxClients; i++) 
  {
    if (IsClientInGame(i)) 
    {
      OnClientPutInServer(i);
    }
  }
}

// UPDATER Integration
public void OnLibraryAdded(const char[] sName) 
{
#if defined _updater_included
  if (!strcmp(sName, "updater")) 
  {
    Updater_AddPlugin(UPDATE_URL);
  }
#endif
}

public void OnAllPluginsLoaded() 
{
#if defined _updater_included
  if (LibraryExists("updater")) 
  {
    Updater_AddPlugin(UPDATE_URL);
  }
#endif
}

#if defined _updater_included
public Action Updater_OnPluginDownloading() 
{
  return gCV_AutoUpdate.BoolValue ? Plugin_Continue : Plugin_Handled;
}

public void Updater_OnPluginUpdated()
{
  char sFilename[64]; 
  GetPluginFilename(null, sFilename, sizeof(sFilename));
  ServerCommand("sm plugins unload %s", sFilename);
  ServerCommand("sm plugins load %s", sFilename);
}
#endif

public void OnMapStart()
{
  if (!gCV_Enable.BoolValue)
    return;
  
  PrecacheParticleSystem(PARTICLE_GHOST); 
  PrecacheSound(DASH_SOUND);
}

public void OnClientPutInServer(int client)
{
  if (!gCV_Enable.BoolValue)
    return;

  // Reset player data
  g_iPlayerDashes[client] = 0;
  g_bPlayerHasEyes[client] = false;

  SDKHook(client, SDKHook_PreThink, Client_OnThink);
}

public void OnClientDisconnect(int client)
{
  // Clean up any eye glow particles
  RemoveEyeGlow(client);
}

public void Client_OnThink(int client)
{
  if (IsHoldingHalfZatoichi(client))
  {
    Hud_Think(client);
  }
}

void Hud_Think(int client)
{
  char sMessage[128];
  int iColor[4] = {0, 255, 255, 255};
  Format(sMessage, sizeof(sMessage), "Dashes: %d/%d\nHit to gain a dash\nPress R to dash slice!", 
         g_iPlayerDashes[client], MAX_DASHES);
  
  SetHudTextParams(-1.0, 0.77, 0.2, iColor[0], iColor[1], iColor[2], iColor[3]);
  ShowHudText(client, 4, sMessage);
}

void CreateEyeGlow(int client)
{
  // Remove existing eye glow first
  RemoveEyeGlow(client);

  char sAttachment[16];
  for (int i = 0; i <= 1; i++)
  {
    strcopy(sAttachment, sizeof(sAttachment), (i == 0) ? "lefteye" : "righteye");

    int particle = TF2_SpawnParticle("halloween_boss_eye_glow", .entity = client, .attachment = sAttachment);
    SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", client);

    if (GetEdictFlags(particle) & FL_EDICT_ALWAYS)
       SetEdictFlags(particle, GetEdictFlags(particle) & ~FL_EDICT_ALWAYS);

    SDKHook(particle, SDKHook_SetTransmit, EyeGlow_SetTransmit);
  }
}

void RemoveEyeGlow(int client)
{
  char sEffectName[64];
  int particle = MaxClients + 1;
  
  while ((particle = FindEntityByClassname(particle, "info_particle_system")) > MaxClients)
  {
    if (GetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity") != client)
      continue;

    GetEntPropString(particle, Prop_Data, "m_iszEffectName", sEffectName, sizeof(sEffectName));
    if (strcmp(sEffectName, "halloween_boss_eye_glow") == 0)
    {
      RemoveEntity(particle);
    }
  }
}

Action EyeGlow_SetTransmit(int entity, int client)
{
  if (GetEdictFlags(entity) & FL_EDICT_ALWAYS)
     SetEdictFlags(entity, GetEdictFlags(entity) & ~FL_EDICT_ALWAYS);

  int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
  if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
  {
    RemoveEntity(entity);
    return Plugin_Handled;
  }

  // Hide from owner unless in taunt cam
  if (client == owner && GetEntProp(client, Prop_Send, "m_nForceTauntCam") == 0)
    return Plugin_Handled;

  // Hide from spectator in first person
  if (!IsPlayerAlive(client) && GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") == owner)
  {
    if (GetEntProp(client, Prop_Send, "m_iObserverMode") == 4) // SPEC_MODE_FIRSTPERSON
      return Plugin_Handled;
  }

  return Plugin_Continue;
}

bool TraceFilter_IgnorePlayers(int entity, int mask, int data)
{
  // Don't hit the dasher or any players
  return (entity != data && (entity < 1 || entity > MaxClients));
}

void PerformTeleport(int client)
{
  float eyePos[3], angles[3];
  GetClientEyePosition(client, eyePos);
  GetClientEyeAngles(client, angles);

  // Calculate direction and max end position
  float direction[3];
  GetAngleVectors(angles, direction, NULL_VECTOR, NULL_VECTOR);
  
  float maxDistance = gCV_DashDistance.FloatValue;
  float maxEndPos[3];
  for (int i = 0; i < 3; i++)
  {
    maxEndPos[i] = eyePos[i] + (direction[i] * maxDistance);
  }

  // Trace ray with limited distance, ignoring players
  TR_TraceRayFilter(eyePos, maxEndPos, MASK_PLAYERSOLID, 
                    RayType_EndPoint, TraceFilter_IgnorePlayers, client);
  
  float endPos[3];
  if (!TR_DidHit())
  {
    // Use max distance if no collision
    endPos = maxEndPos;
  }
  else
  {
    TR_GetEndPosition(endPos);
  }
  
  float origin[3], mins[3], maxs[3];
  GetClientAbsOrigin(client, origin);
  GetClientMins(client, mins);
  GetClientMaxs(client, maxs);

  // Spawn ghost particle at original position
  CreateTimer(3.0, Timer_EntityCleanup, TF2_SpawnParticle(PARTICLE_GHOST, origin, angles));

  // Prevent downward teleports
  if (endPos[2] < origin[2])
    endPos[2] = origin[2];

  // Hull trace for player collision
  TR_TraceHullFilter(origin, endPos, mins, maxs, MASK_PLAYERSOLID, TraceFilter_IgnorePlayers, client);
  TR_GetEndPosition(endPos);

  // Find the floor
  float floorAngles[3] = {90.0, 0.0, 0.0};
  TR_TraceRayFilter(endPos, floorAngles, MASK_PLAYERSOLID, RayType_Infinite, TraceFilter_IgnorePlayers, client);
  
  if (TR_DidHit())
  {
    float floorPos[3];
    TR_GetEndPosition(floorPos);
    TR_TraceHullFilter(endPos, floorPos, mins, maxs, MASK_PLAYERSOLID, TraceFilter_IgnorePlayers, client);
    TR_GetEndPosition(endPos);
  }

  // Damage enemies along the dash path
  DamagePlayersAlongPath(client, origin, endPos);

  // Spawn ghost particle at new position
  CreateTimer(3.0, Timer_EntityCleanup, TF2_SpawnParticle(PARTICLE_GHOST, endPos, angles));

  // Play sound and teleport
  EmitGameSoundToAll(DASH_SOUND, client);
  TeleportEntity(client, endPos, NULL_VECTOR, NULL_VECTOR);
}

void DamagePlayersAlongPath(int client, float start[3], float end[3])
{
  int clientTeam = GetClientTeam(client);
  int hitPlayers = 0;
  
  for (int target = 1; target <= MaxClients; target++)
  {
    if (!IsClientInGame(target) || !IsPlayerAlive(target) || target == client)
      continue;
      
    // Skip teammates
    if (GetClientTeam(target) == clientTeam)
      continue;
    
    float targetPos[3], targetMins[3], targetMaxs[3];
    GetClientAbsOrigin(target, targetPos);
    GetClientMins(target, targetMins);
    GetClientMaxs(target, targetMaxs);
    
    // Convert to world coordinates
    for (int i = 0; i < 3; i++)
    {
      targetMins[i] += targetPos[i];
      targetMaxs[i] += targetPos[i];
    }
    
    // Check if dash path intersects with target
    if (IsLineIntersectingBox(start, end, targetMins, targetMaxs))
    {
      // Deal damage
      int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
      SDKHooks_TakeDamage(target, client, client, float(DASH_DAMAGE), DMG_SLASH, weapon);
      
      hitPlayers++;
      
      // Create hit effect
      CreateTimer(2.0, Timer_EntityCleanup, TF2_SpawnParticle("crit_text", targetPos));
    }
  }
  
  if (hitPlayers > 0)
  {
    PrintHintText(client, "Dash Strike! Hit %d enemies", hitPlayers);
  }
}

bool IsLineIntersectingBox(float lineStart[3], float lineEnd[3], float boxMin[3], float boxMax[3])
{
  float tMin = 0.0, tMax = 1.0;
  
  for (int i = 0; i < 3; i++)
  {
    float dir = lineEnd[i] - lineStart[i];
    if (dir == 0.0) continue; // Parallel to axis
    
    float invDir = 1.0 / dir;
    float t1 = (boxMin[i] - lineStart[i]) * invDir;
    float t2 = (boxMax[i] - lineStart[i]) * invDir;
    
    if (invDir < 0.0)
    {
      float temp = t1;
      t1 = t2;
      t2 = temp;
    }
    
    if (t1 > tMin) tMin = t1;
    if (t2 < tMax) tMax = t2;
    
    if (tMin > tMax) return false;
  }
  
  return true;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, 
                            float vel[3], float angles[3], int &weapon,
                            int &subtype, int &cmdnum, int &tickcount,
                            int &seed, int mouse[2]) 
{  
  if (!gCV_Enable.BoolValue || !IsClientInGame(client) || !IsPlayerAlive(client))
    return Plugin_Continue;

  // Check for dash input
  if (g_iPlayerDashes[client] > 0 && IsHoldingHalfZatoichi(client) && 
      (buttons & IN_RELOAD) && !(g_iPlayerLastButtons[client] & IN_RELOAD))
  {
    // Prevent dashing when stunned
    if (TF2_IsPlayerInCondition(client, TFCond_Dazed))
    {
      PrintHintText(client, "Can't teleport when stunned.");
    }
    else
    {
      g_iPlayerDashes[client]--;
      PerformTeleport(client);
    }
  }

  g_iPlayerLastButtons[client] = buttons;
  return Plugin_Continue;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
  if (!gCV_Enable.BoolValue)
    return;

  // Reset all player data
  for (int i = 1; i <= MaxClients; i++)
  {
    if (IsClientInGame(i))
    {
      g_iPlayerDashes[i] = 0;
      g_bPlayerHasEyes[i] = false;
      RemoveEyeGlow(i);
    }
  }
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast) 
{
  if (!gCV_Enable.BoolValue)
    return Plugin_Continue;

  int victim = GetClientOfUserId(event.GetInt("userid"));
  int attacker = GetClientOfUserId(event.GetInt("attacker"));

  if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && 
      victim != attacker && IsHoldingHalfZatoichi(attacker))
  {
    // Grant dash charge (up to maximum)
    if (g_iPlayerDashes[attacker] < MAX_DASHES)
    {
      g_iPlayerDashes[attacker]++;
    }
    
    // Create eye glow effect
    if (g_iPlayerDashes[attacker] > 0 && !g_bPlayerHasEyes[attacker])
    {
      CreateEyeGlow(attacker);
      g_bPlayerHasEyes[attacker] = true;
    }
  }

  return Plugin_Continue;
}

public Action Timer_EntityCleanup(Handle timer, int entityRef)
{
  int entity = EntRefToEntIndex(entityRef);
  if (entity > MaxClients && IsValidEntity(entity))
  {
    AcceptEntityInput(entity, "Kill");
  }
  return Plugin_Handled;
}

stock int TF2_SpawnParticle(const char[] particle, float origin[3] = NULL_VECTOR, 
                           float angles[3] = NULL_VECTOR, bool activate = true, 
                           int entity = 0, int controlPoint = 0, 
                           const char[] attachment = "", const char[] attachmentOffset = "")
{
  int particleEntity = CreateEntityByName("info_particle_system");
  TeleportEntity(particleEntity, origin, angles, NULL_VECTOR);
  DispatchKeyValue(particleEntity, "effect_name", particle);
  DispatchSpawn(particleEntity);
  
  if (entity > 0 && IsValidEntity(entity))
  {
    SetVariantString("!activator");
    AcceptEntityInput(particleEntity, "SetParent", entity);

    if (attachment[0])
    {
      SetVariantString(attachment);
      AcceptEntityInput(particleEntity, "SetParentAttachment", particleEntity);
    }
    
    if (attachmentOffset[0])
    {
      SetVariantString(attachmentOffset);
      AcceptEntityInput(particleEntity, "SetParentAttachmentMaintainOffset", particleEntity);
    }
  }
  
  if (controlPoint > 0 && IsValidEntity(controlPoint))
  {
    SetEntPropEnt(particleEntity, Prop_Send, "m_hControlPointEnts", controlPoint, 0);
    SetEntProp(particleEntity, Prop_Send, "m_iControlPointParents", controlPoint, _, 0);
  }
  
  if (activate)
  {
    ActivateEntity(particleEntity);
    AcceptEntityInput(particleEntity, "Start");
  }
  
  return EntIndexToEntRef(particleEntity);
}

stock bool IsHoldingHalfZatoichi(int client) 
{
  int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
  if (weapon > MaxClients && IsValidEntity(weapon)) 
  {
    return GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == HALF_ZATOICHI;
  }
  return false;
}

stock int PrecacheParticleSystem(const char[] particleSystem)
{
  static int particleEffectNames = INVALID_STRING_TABLE;
  if (particleEffectNames == INVALID_STRING_TABLE)
  {
    particleEffectNames = FindStringTable("ParticleEffectNames");
    if (particleEffectNames == INVALID_STRING_TABLE)
    {
      return INVALID_STRING_INDEX;
    }
  }

  int index = FindStringIndex2(particleEffectNames, particleSystem);
  if (index == INVALID_STRING_INDEX)
  {
    int numStrings = GetStringTableNumStrings(particleEffectNames);
    if (numStrings >= GetStringTableMaxStrings(particleEffectNames))
    {
      return INVALID_STRING_INDEX;
    }

    AddToStringTable(particleEffectNames, particleSystem);
    index = numStrings;
  }

  return index;
}

stock int FindStringIndex2(int tableidx, const char[] str)
{
  char buf[1024];
  int numStrings = GetStringTableNumStrings(tableidx);
  for (int i = 0; i < numStrings; i++)
  {
    ReadStringTable(tableidx, i, buf, sizeof(buf));
    if (StrEqual(buf, str))
    {
      return i;
    }
  }

  return INVALID_STRING_INDEX;
}
