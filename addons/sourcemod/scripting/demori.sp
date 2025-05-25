#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>

public Plugin myinfo = {
  name        = "Demori",
  author      = "Koto, Aidan Sanders",
  description = "Half Demoman, Half Samurai, All Trouble.",
  version     = "1.3",
  url         = "https://github.com/issari-tf/Demorai"
};

#define HALF_ZATOICHI 357

#define PARTICLE_GHOST "ghost_appearation"
#define DASH_SOUND     "Halloween.spell_teleport"

// Player Data
int g_iPlayerDashes[MAXPLAYERS];
int g_iPlayerLastButtons[MAXPLAYERS];
bool g_bPlayerHasEyes[MAXPLAYERS];

public void OnPluginStart()
{
  HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_Pre);
  HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);

  // Incase of lateload, call client join functions
  for (int iClient = 1; iClient <= MaxClients; iClient++) 
  {
    if (IsClientInGame(iClient)) 
    {
      OnClientPutInServer(iClient);
    }
  }
}

public void OnMapStart()
{
  PrecacheParticleSystem(PARTICLE_GHOST); 
  PrecacheSound(DASH_SOUND);
}

public void OnClientPutInServer(int iClient)
{
  // Reset
  g_iPlayerDashes[iClient] = 0;
  g_bPlayerHasEyes[iClient] = false;

  SDKHook(iClient, SDKHook_PreThink, Client_OnThink);
}

public void Client_OnThink(int iClient)
{
  if (!IsHoldingHalfZatoichi(iClient))
    return;

  Hud_Think(iClient);
}

void Hud_Think(int iClient)
{
  char sMessage[256];
  int iColor[4] = {255, 255, 255, 255};
  Format(sMessage, sizeof(sMessage), "Dashes: %d\nHit to gain a dash\nPress R to dash slice!", g_iPlayerDashes[iClient]);
  Hud_Display(iClient, 4, sMessage, view_as<float>({-1.0, 0.77}), 0.2, iColor);
}

void Hud_Display(int iClient, int iChannel, char[] sText, float flHUD[2], float flDuration = 0.0, int iColor[4] = {255, 255, 255, 255}, int iEffect = 0, float flTime = 0.0, float flFade[2] = {0.0, 0.0})
{
  SetHudTextParams(flHUD[0], flHUD[1], flDuration, iColor[0], iColor[1], iColor[2], iColor[3], iEffect, flTime, flFade[0], flFade[1]);
  ShowHudText(iClient, iChannel, sText);
}

void Client_CreateEyeGlow(int iClient)
{
  char sEffectName[64];
  int iParticle = MaxClients + 1;
  while ((iParticle = FindEntityByClassname(iParticle, "info_particle_system")) > MaxClients)
  {
    if (GetEntPropEnt(iParticle, Prop_Send, "m_hOwnerEntity") != iClient)
      continue;

    GetEntPropString(iParticle, Prop_Data, "m_iszEffectName", sEffectName, sizeof(sEffectName));
    if (strcmp(sEffectName, "halloween_boss_eye_glow") != 0)
      continue;

    RemoveEntity(iParticle);
  }

  char sAttachment[64];
  for (int i = 0; i <= 1; i++)
  {
    strcopy(sAttachment, sizeof(sAttachment), (i == 0) ? "lefteye" : "righteye");

    iParticle = TF2_SpawnParticle("halloween_boss_eye_glow", .iEntity = iClient, .sAttachment = sAttachment);
    SetEntPropEnt(iParticle, Prop_Send, "m_hOwnerEntity", iClient);

    if (GetEdictFlags(iParticle) & FL_EDICT_ALWAYS)
       SetEdictFlags(iParticle, GetEdictFlags(iParticle) & ~FL_EDICT_ALWAYS);

    SDKHook(iParticle, SDKHook_SetTransmit, Client_EyeGlowTransmit);
  }
}

Action Client_EyeGlowTransmit(int iEntity, int iClient)
{
  if (GetEdictFlags(iEntity) & FL_EDICT_ALWAYS)
     SetEdictFlags(iEntity, GetEdictFlags(iEntity) & ~FL_EDICT_ALWAYS);

  int iOwner = GetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity");
  if (iOwner <= 0 || iOwner > MaxClients || !IsClientInGame(iOwner))
	{
    RemoveEntity(iEntity);
    return Plugin_Handled;
  }

  if (iClient == iOwner && GetEntProp(iClient, Prop_Send, "m_nForceTauntCam") == 0)
    return Plugin_Handled;

  if (!IsPlayerAlive(iClient) && GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget") == iOwner)
  {
    if (GetEntProp(iClient, Prop_Send, "m_iObserverMode") == 4)	//SPEC_MODE_FIRSTPERSON
      return Plugin_Handled;
  }

  return Plugin_Continue;
}

void PerformTeleport(int iClient)
{
  float vecEyePos[3], vecAng[3];
  GetClientEyePosition(iClient, vecEyePos);
  GetClientEyeAngles(iClient, vecAng);

  TR_TraceRayFilter(vecEyePos, vecAng, MASK_PLAYERSOLID, 
                    RayType_Infinite, TraceRay_DontHitEntity, 
                    iClient);
  if (!TR_DidHit())
    return;

  float vecEndPos[3];
  TR_GetEndPosition(vecEndPos);
  
  float vecOrigin[3], vecMins[3], vecMaxs[3];
  GetClientAbsOrigin(iClient, vecOrigin);
  GetClientMins(iClient, vecMins);
  GetClientMaxs(iClient, vecMaxs);

  // Create particle -> original position
  CreateTimer(3.0, Timer_EntityCleanup, TF2_SpawnParticle(PARTICLE_GHOST, vecOrigin, vecAng));

  // If trace heading downward, prevent that because mins/maxs hitbox
  if (vecEndPos[2] < vecOrigin[2])
    vecEndPos[2] = vecOrigin[2];

  // Find spot from player's eye
  TR_TraceHullFilter(vecOrigin, vecEndPos, vecMins, vecMaxs,
                     MASK_PLAYERSOLID, TraceRay_DontHitEntity, 
                     iClient);
  TR_GetEndPosition(vecEndPos);

  // Find the floor
  TR_TraceRayFilter(vecEndPos, view_as<float>({ 90.0, 0.0, 0.0 }), 
                    MASK_PLAYERSOLID, RayType_Infinite, TraceRay_DontHitEntity, 
                    iClient);
  if (!TR_DidHit())
    return;

  float vecFloorPos[3];
  TR_GetEndPosition(vecFloorPos);
  TR_TraceHullFilter(vecEndPos, vecFloorPos, vecMins, vecMaxs, 
                     MASK_PLAYERSOLID, TraceRay_DontHitEntity, 
                     iClient);
  TR_GetEndPosition(vecEndPos);

  // Create particle -> new position
  CreateTimer(3.0, Timer_EntityCleanup, TF2_SpawnParticle(PARTICLE_GHOST, vecEndPos, vecAng));

  // Play a sound
  EmitGameSoundToAll(DASH_SOUND, iClient);

  // Teleport Client
  TeleportEntity(iClient, vecEndPos, NULL_VECTOR, NULL_VECTOR);
}

public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, 
                             float vel[3], float angles[3], int &weapon,
                             int &subtype, int &cmdnum, int &tickcount,
                             int &seed, int mouse[2]) 
{  
  if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient) || !IsPlayerAlive(iClient)) 
    return Plugin_Continue;

  if (g_iPlayerDashes[iClient] > 0 
   && IsHoldingHalfZatoichi(iClient) 
   && (buttons & IN_RELOAD) != 0 
   && g_iPlayerLastButtons[iClient] != buttons)
  {
    // Deny teleporting when stunned
    if (TF2_IsPlayerInCondition(iClient, TFCond_Dazed))
    {
      PrintHintText(iClient, "Can't teleport when stunned.");
      return Plugin_Continue;
    }

    g_iPlayerDashes[iClient]--;
    PerformTeleport(iClient);
  }

  g_iPlayerLastButtons[iClient] = buttons;
  return Plugin_Continue;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
  for (int iClient = 1; iClient <= MaxClients; iClient++)
  {
    if (IsClientInGame(iClient))
    {
      g_iPlayerDashes[iClient] = 0;
      g_bPlayerHasEyes[iClient] = false;
    }
  }
}

public Action Event_PlayerHurt(Event event, const char[] sName, bool bDontBroadcast) 
{
  int iClient = GetClientOfUserId(event.GetInt("userid"));
  int iAttacker = GetClientOfUserId(event.GetInt("attacker"));

  if (0 < iAttacker <= MaxClients && IsClientInGame(iAttacker) && iClient != iAttacker)
  {
    if (IsHoldingHalfZatoichi(iAttacker))
    {
      g_iPlayerDashes[iAttacker]++;
      if (g_iPlayerDashes[iAttacker] != 0 && !g_bPlayerHasEyes[iAttacker])
      {
        Client_CreateEyeGlow(iAttacker);
        g_bPlayerHasEyes[iAttacker] = true;
      }
    }
  }

  return Plugin_Continue;
}

public Action Timer_EntityCleanup(Handle hTimer, int iRef)
{
  int iEntity = EntRefToEntIndex(iRef);
  if(iEntity > MaxClients)
    AcceptEntityInput(iEntity, "Kill");
  return Plugin_Handled;
}

stock int TF2_SpawnParticle(char[] sParticle, float vecOrigin[3] = NULL_VECTOR, float vecAngles[3] = NULL_VECTOR, bool bActivate = true, int iEntity = 0, int iControlPoint = 0, const char[] sAttachment = "", const char[] sAttachmentOffset = "")
{
  int iParticle = CreateEntityByName("info_particle_system");
  TeleportEntity(iParticle, vecOrigin, vecAngles, NULL_VECTOR);
  DispatchKeyValue(iParticle, "effect_name", sParticle);
  DispatchSpawn(iParticle);
  
  if (0 < iEntity && IsValidEntity(iEntity))
  {
    SetVariantString("!activator");
    AcceptEntityInput(iParticle, "SetParent", iEntity);

    if (sAttachment[0])
    {
      SetVariantString(sAttachment);
      AcceptEntityInput(iParticle, "SetParentAttachment", iParticle);
    }
    
    if (sAttachmentOffset[0])
    {
      SetVariantString(sAttachmentOffset);
      AcceptEntityInput(iParticle, "SetParentAttachmentMaintainOffset", iParticle);
    }
  }
  
  if (0 < iControlPoint && IsValidEntity(iControlPoint))
  {
    //Array netprop, but really only need element 0 anyway
    SetEntPropEnt(iParticle, Prop_Send, "m_hControlPointEnts", iControlPoint, 0);
    SetEntProp(iParticle, Prop_Send, "m_iControlPointParents", iControlPoint, _, 0);
  }
  
  if (bActivate)
  {
    ActivateEntity(iParticle);
    AcceptEntityInput(iParticle, "Start");
  }
  
  //Return ref of entity
  return EntIndexToEntRef(iParticle);
}

stock bool IsHoldingHalfZatoichi(int iClient) 
{
  int iWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
  if (iWeapon > MaxClients && IsValidEntity(iWeapon)) 
  {
    int iIndex = GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex");
    return iIndex == HALF_ZATOICHI;
  }
  return false;
}

stock int PrecacheParticleSystem(const char[] particleSystem)
{
  static int particleEffectNames = INVALID_STRING_TABLE;
  if (particleEffectNames == INVALID_STRING_TABLE)
  {
    if ((particleEffectNames = FindStringTable("ParticleEffectNames")) == INVALID_STRING_TABLE)
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

stock bool TraceRay_DontHitEntity(int iEntity, int iMask, int iData)
{
  return iEntity != iData;
}