/*
 * Author contact: http://t.me/twisternick or:
 *	- Official topic of the resource in Russian forum: https://dev-cs.ru/threads/3944/
 *	- Official topic of the resource in English forum: https://forums.alliedmods.net/showthread.php?p=2626738#post2626738
 *	- Official topic of the resource in Spanish forum: https://amxmodx-es.com/Thread-Admin-Commands-Log-v1-0
 *
 * Idea: DrStrange. Topic: https://dev-cs.ru/threads/3792/
 *
 * Credits to:
 *	- mx?!
 *	- wopox1337
 *	- F@nt0m (reloadcfg/readcfg methods)
 *
 * Changelog:
 *	- 1.1: Fixed two errors: getting the values of the cvars, creating log files.
 *	- 1.0:
 *		- Removed AMX Mod X 1.8.2/1.8.3 support.
 *		- Defines are replaced by CVars.
 *		- Added automatic creation and execution of a configuration file with CVars: "amxmodx/configs/plugins/admin_commands_log.cfg".
 *		- CVars' description are in "data/lang/admin_commands.log.txt" (multilang added).
 *		- Thanks to F@nt0m:
 *			- g_szCmds array changed to acl_list.ini (you can add commands in "amxmodx/configs/acl_list.ini").
 *			- Added "acl_reloadcfg" command.
 *	- 0.3: Fixed 2 errors regarding LOG_FORMAT define (thanks to DrStrange for bug-report).
 *	- 0.2:
 *		- Fixed an error with AMX Mod X 1.8.3. I still recommend to upgrade your server to AMX Mod X 1.9.0 or higher.
 *		- Added two settings:
 *			- TYPE_CMDS_LOG (logging commands which starts with "amx_" or only commands from array g_szCmds).
 *			- LOG_FORMAT (0 - log to a file; 1 - log to a file created every day in folder g_szLogFileFolder; 2 - log to a file created every month in folder g_szLogFileFolder).
 *	- 0.1: Release.
 */

#include <amxmodx>

#pragma semicolon 1

#define PLUGIN_VERSION "1.1"

/****************************************************************************************
****************************************************************************************/

// Filename for cfg file where you can add commands (CVar acl_type = )
new const g_szCfgFileName[] = "acl_list.ini";

new g_szLogFile[PLATFORM_MAX_PATH];
new g_iCvarType;
// acl_type = 2 || acl_type = 3
new g_szCommands[256][64], g_iCommandsNum;
new g_iAccess = (ADMIN_KICK|ADMIN_BAN|ADMIN_CFG|ADMIN_RCON|ADMIN_LEVEL_A);

public plugin_init()
{
	register_plugin("Admin Commands Log", PLUGIN_VERSION, "w0w");
	register_dictionary("admin_commands_log.txt");

	new pCvar;

	// 0 - logging all commands which starts with "amx_"; 1 - logging all commands from the cfg file; 2 - values 0 and 1 of this CVar are combined
	create_cvar("acl_type", "0", FCVAR_NONE, fmt("%l", "ACL_CVAR_TYPE"), true, 0.0, true, 2.0);

	// Logging will only for for players who has one of the specified flags
	pCvar = create_cvar("acl_access", "cdhlm", FCVAR_NONE, fmt("%l", "ACL_CVAR_ACCESS"));
	hook_cvar_change(pCvar, "hook_CvarChange_Access");

	// 0 - log all commands to a file; 1 - log all commands to a different file created every day; 2 - log all commands to a different file created every month
	create_cvar("acl_log_type", "0", FCVAR_NONE, fmt("%l", "ACL_CVAR_LOG_TYPE"), true, 0.0, true, 2.0);
	// Flag to use the command acl_reloadcfg
	create_cvar("acl_reloadcfg_access", "h", FCVAR_NONE, fmt("%l", "ACL_CVAR_RELOADCFG_ACCESS"));

	AutoExecConfig(true, "admin_commands_log");
}

public OnConfigsExecuted()
{
	g_iCvarType = get_cvar_num("acl_type");

	if(g_iCvarType != 0 && !func_ReadCfgFile())
		set_fail_state("[ACL]: Error load cfg ^"%s^"", g_szCfgFileName);

	new pCvarReloadCfg, szCvarReloadCfg[32];
	pCvarReloadCfg = get_cvar_pointer("acl_reloadcfg_access");
	get_pcvar_string(pCvarReloadCfg, szCvarReloadCfg, charsmax(szCvarReloadCfg));

	register_concmd("acl_reloadcfg", "func_ConCmdReloadCfg", read_flags(szCvarReloadCfg));

	new iCvarLogType = get_cvar_num("acl_log_type");

	new szPath[PLATFORM_MAX_PATH], szFileName[64];
	get_localinfo("amxx_logs", szPath, charsmax(szPath));

	switch(iCvarLogType)
	{
		case 0: g_szLogFile = "admin_commands.log";
		case 1: szFileName = "/admin_commands_%d-%m-%Y.log";
		case 2: szFileName = "/admin_commands_%m-%Y.log";
	}

	if(iCvarLogType != 0)
	{
		add(szPath, charsmax(szPath), "/admin_commands");

		if(!dir_exists(szPath))
			mkdir(szPath);

		add(szPath, charsmax(szPath), szFileName);
		get_time(szPath, g_szLogFile, charsmax(g_szLogFile));
	}

	new pCvar = register_cvar("acl_version", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY);
	set_pcvar_string(pCvar, PLUGIN_VERSION);
}

public client_command(id)
{
	if(!(get_user_flags(id) & g_iAccess))
		return PLUGIN_CONTINUE;

	enum { command = 0 };

	new szCommand[64];
	read_argv(command, szCommand, charsmax(szCommand));

	switch(g_iCvarType)
	{
		case 0:
		{
			if(containi(szCommand, "amx_") == -1 || !szCommand[4])
				return PLUGIN_CONTINUE;
		}
		case 1:
		{
			if(!func_CommandInList(szCommand))
				return PLUGIN_CONTINUE;
		}
		case 2:
		{
			if(!func_CommandInList(szCommand) && containi(szCommand, "amx_") == -1)
				return PLUGIN_CONTINUE;
		}
	}

	new szArgs[64];
	read_args(szArgs, charsmax(szArgs));

	if(szArgs[0])
		func_LogToFile(id, szCommand, szArgs);
	else
		func_LogToFile(id, szCommand);

	return PLUGIN_CONTINUE;
}

func_LogToFile(id, szCommand[], szArgs[] = "")
{
	new szAuthID[MAX_AUTHID_LENGTH], szIP[MAX_IP_LENGTH];
	get_user_authid(id, szAuthID, charsmax(szAuthID));
	get_user_ip(id, szIP, charsmax(szIP), 1);

	if(szArgs[0])
		log_to_file(g_szLogFile, "%n (<%s> <%s>) ---> %s %s", id, szAuthID, szIP, szCommand, szArgs);
	else
		log_to_file(g_szLogFile, "%n (<%s> <%s>) ---> %s", id, szAuthID, szIP, szCommand);
}

// F@nt0m's code ( https://dev-cs.ru/threads/2672/#post-30421 )
public func_ConCmdReloadCfg(id, lvl, cid)
{
	if(!(get_user_flags(id) & lvl))
		console_print(id, "[ACL]: You have not access to this command");
	else if(!func_ReadCfgFile())
		console_print(id, "[ACL]: Error load cfg ^"%s^"", g_szCfgFileName);
	else
		console_print(id, "[ACL]: Reload cfg ^"%s^"", g_szCfgFileName);

	return PLUGIN_HANDLED;
}

bool:func_ReadCfgFile()
{
	new szConfigsDir[PLATFORM_MAX_PATH], szFilePath[PLATFORM_MAX_PATH];
	get_localinfo("amxx_configsdir", szConfigsDir, charsmax(szConfigsDir));
	formatex(szFilePath, charsmax(szFilePath), "%s/%s", szConfigsDir, g_szCfgFileName);

	new iFileHandle = fopen(szFilePath, "rt");
	if(!iFileHandle)
		return false;

	g_iCommandsNum = 0;

	new szString[256];
	while(!feof(iFileHandle))
	{
		fgets(iFileHandle, szString, charsmax(szString));
		trim(szString);

		if(szString[0] == EOS || szString[0] == ';')
			continue;
 
		remove_quotes(szString);
 
		copy(g_szCommands[g_iCommandsNum], sizeof g_szCommands[], szString);
		g_iCommandsNum++;
 
		if(g_iCommandsNum >= sizeof g_szCommands)
			break;
	}

	fclose(iFileHandle);
	return true;
}

bool:func_CommandInList(const szCommand[])
{
    for(new i; i < g_iCommandsNum; i++)
	{
        if(equal(g_szCommands[i], szCommand))
            return true;
    }
    return false;
}

public hook_CvarChange_Access(pCvar, const szOldValue[], const szNewValue[])
{
	g_iAccess = read_flags(szNewValue);
}