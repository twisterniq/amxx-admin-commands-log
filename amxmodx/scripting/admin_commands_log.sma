/*
 * Credits to:
 *	- DrStrange (the idea)
 *	- mx?!
 *	- wopox1337
 *	- F@nt0m (reloadcfg/readcfg methods)
 */

#include <amxmodx>

#pragma semicolon 1

public stock const PluginName[] = "Admin Commands Log";
public stock const PluginVersion[] = "1.2.1";
public stock const PluginAuthor[] = "twisterniq";
public stock const PluginURL[] = "https://github.com/twisterniq/amxx-admin-commands-log";
public stock const PluginDescription[] = "Adds the ability to log the commands that put players with access";

new const CONFIG_NAME[] = "admin_commands_log";
new const LIST_CONFIG_NAME[] = "acl_list.ini";

new Trie:g_tCommands;

new g_iType;

enum _:TYPES
{
	TYPE_START_AMX = 0,
	TYPE_FILE,
	TYPE_COMBINED
};

new g_iAccess = (ADMIN_KICK|ADMIN_BAN|ADMIN_CFG|ADMIN_RCON|ADMIN_LEVEL_A);
new g_iReloadCfgAccess = ADMIN_CFG;
new g_szLogFile[PLATFORM_MAX_PATH];

public plugin_init()
{
#if AMXX_VERSION_NUM == 190
	register_plugin(
		.plugin_name = PluginName,
		.version = PluginVersion,
		.author = PluginAuthor);
#endif

	register_dictionary("admin_commands_log.txt");

	register_concmd("acl_reloadcfg", "@func_ConCmdReloadCfg");

	g_tCommands = TrieCreate();

	new pCvar, iLogType;

	pCvar = create_cvar(
		.name = "acl_type",
		.string = "0",
		.flags = FCVAR_NONE,
		.description = fmt("%L", LANG_SERVER,  "ACL_CVAR_TYPE"),
		.has_min = true,
		.min_val = 0.0,
		.has_max = true,
		.max_val = 2.0);
	g_iType = get_pcvar_num(pCvar);

	pCvar = create_cvar(
		.name = "acl_access",
		.string = "cdhlm",
		.flags = FCVAR_NONE,
		.description = fmt("%L", LANG_SERVER, "ACL_CVAR_ACCESS"));
	set_pcvar_string(pCvar, "");
	hook_cvar_change(pCvar, "@OnAccessChange");

	pCvar = create_cvar(
		.name = "acl_log_type",
		.string = "0",
		.flags = FCVAR_NONE,
		.description = fmt("%L", LANG_SERVER, "ACL_CVAR_LOG_TYPE"),
		.has_min = true,
		.min_val = 0.0,
		.has_max = true,
		.max_val = 2.0);
	iLogType = get_pcvar_num(pCvar);

	pCvar = create_cvar(
		.name = "acl_reloadcfg_access",
		.string = "h",
		.flags = FCVAR_NONE,
		.description = fmt("%L", LANG_SERVER, "ACL_CVAR_RELOADCFG_ACCESS"));
	set_pcvar_string(pCvar, "");
	hook_cvar_change(pCvar, "@OnReloadCfgAccessChange");

	AutoExecConfig(true, "admin_commands_log");

	new szPath[PLATFORM_MAX_PATH];

	get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
	server_cmd("exec %s/plugins/%s.cfg", szPath, CONFIG_NAME);
	server_exec();

	if (g_iType != TYPE_START_AMX && !func_ReadCfgFile())
	{
		set_fail_state("[ACL]: An error ocurred loading cfg ^"%s^"", LIST_CONFIG_NAME);
	}

	new szFileName[64];
	get_localinfo("amxx_logs", szPath, charsmax(szPath));

	enum { LOG_ALL = 0, LOG_DAILY, LOG_MONTHLY };

	switch (iLogType)
	{
		case LOG_ALL:
		{
			g_szLogFile = "admin_commands.log";
		}
		case LOG_DAILY:
		{
			szFileName = "/admin_commands_%d-%m-%Y.log";
		}
		case LOG_MONTHLY:
		{
			szFileName = "/admin_commands_%m-%Y.log";
		}
	}

	if (iLogType != LOG_ALL)
	{
		add(szPath, charsmax(szPath), "/admin_commands");

		if (!dir_exists(szPath))
		{
			mkdir(szPath);
		}

		add(szPath, charsmax(szPath), szFileName);
		get_time(szPath, g_szLogFile, charsmax(g_szLogFile));
	}
}

public client_command(id)
{
	if (g_iAccess > 0 && !(get_user_flags(id) & g_iAccess))
	{
		return PLUGIN_CONTINUE;
	}

	enum { arg_command = 0 };

	new szCommand[64];
	read_argv(arg_command, szCommand, charsmax(szCommand));

	switch (g_iType)
	{
		case TYPE_START_AMX:
		{
			if (containi(szCommand, "amx_") == -1 || !szCommand[4])
			{
				return PLUGIN_CONTINUE;
			}
		}
		case TYPE_FILE:
		{
			if (!TrieKeyExists(g_tCommands, szCommand))
			{
				return PLUGIN_CONTINUE;
			}
		}
		case TYPE_COMBINED:
		{
			if (!TrieKeyExists(g_tCommands, szCommand) && containi(szCommand, "amx_") == -1)
			{
				return PLUGIN_CONTINUE;
			}
		}
	}

	new szArgs[64];
	read_args(szArgs, charsmax(szArgs));

	func_LogToFile(id, szCommand, szArgs[0] ? szArgs : "");
	return PLUGIN_CONTINUE;
}

func_LogToFile(const id, szCommand[], szArgs[] = "")
{
	new szAuthID[MAX_AUTHID_LENGTH], szIP[MAX_IP_LENGTH];
	get_user_authid(id, szAuthID, charsmax(szAuthID));
	get_user_ip(id, szIP, charsmax(szIP), 1);

	log_to_file(g_szLogFile, "%n (<%s> <%s>) ---> %s %s", id, szAuthID, szIP, szCommand, szArgs);
}

// thx to F@nt0m (https://dev-cs.ru/threads/2672/#post-30421)
@func_ConCmdReloadCfg(const id)
{
	if (!(get_user_flags(id) & g_iReloadCfgAccess))
	{
		console_print(id, "[ACL]: You have no access to use this command");
	}
	else if (!func_ReadCfgFile())
	{
		console_print(id, "[ACL]: An error ocurred loading cfg ^"%s^"", LIST_CONFIG_NAME);
	}
	else
	{
		console_print(id, "[ACL]: Reloading cfg ^"%s^"", LIST_CONFIG_NAME);
	}

	return PLUGIN_HANDLED;
}

bool:func_ReadCfgFile()
{
	new szPath[PLATFORM_MAX_PATH];
	get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
	format(szPath, charsmax(szPath), "%s/%s", szPath, LIST_CONFIG_NAME);

	new iFileHandle = fopen(szPath, "rt");

	if (!iFileHandle)
	{
		return false;
	}

	new szString[256];

	while(!feof(iFileHandle))
	{
		fgets(iFileHandle, szString, charsmax(szString));
		trim(szString);

		if (szString[0] == EOS || szString[0] == ';')
		{
			continue;
		}
 
		remove_quotes(szString);
 
		TrieSetCell(g_tCommands, szString, 0);
	}

	fclose(iFileHandle);

	return true;
}

@OnAccessChange(const iHandle, const szOldValue[], const szNewValue[])
{
	g_iAccess = read_flags(szNewValue);
}

@OnReloadCfgAccessChange(const iHandle, const szOldValue[], const szNewValue[])
{
	g_iReloadCfgAccess = read_flags(szNewValue);
}
