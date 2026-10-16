#ifndef MAIN_H
#define MAIN_H

#include <stdint.h>
#include "server.h"

class CConfig
{
public:
	bool m_Verbose;
	char m_aConfigFile[1024];
	char m_aWebDir[1024];
	char m_aTemplateFile[1024];
	char m_aJSONFile[1024];
	char m_aBindAddr[256];
	int m_Port;
	int m_Timeout;

	CConfig();
};

class CMain
{
	CConfig m_Config;
	CServer m_Server;

	// 保护 m_aClients：主线程（ReadConfig / HandleMessage / OnNewClient /
	// OnDelClient）负责写入，JSON 更新线程负责读取。
	// 注意：pthread 互斥锁不可重入，因此只在最外层加锁；由主线程同步调用的
	// 回调（OnNewClient / OnDelClient / HandleMessage）内部不得再次加锁。
	LOCK m_ClientLock;

	struct CClient
	{
		bool m_Active;
		bool m_Disabled;
		bool m_Connected;
		int m_ClientNetID;
		int m_ClientNetType;
		char m_aUsername[128];
		char m_aName[128];
		char m_aType[128];
		char m_aHost[128];
		char m_aLocation[128];
		char m_aRegion[128];
		char m_aPassword[128];

		int64 m_TimeConnected;
		int64 m_LastUpdate;

		struct CStats
		{
			bool m_Online4;
			bool m_Online6;
			int64_t m_Uptime;
			double m_Load;
			int64_t m_NetworkRx;
			int64_t m_NetworkTx;
			int64_t m_NetworkIN;
			int64_t m_NetworkOUT;
			int64_t m_MemTotal;
			int64_t m_MemUsed;
			int64_t m_SwapTotal;
			int64_t m_SwapUsed;
			int64_t m_HDDTotal;
			int64_t m_HDDUsed;
			double m_CPU;
			char m_aCustom[512];
			// Options
			bool m_Pong;
		} m_Stats;
	} m_aClients[NET_MAX_CLIENTS];

	struct CJSONUpdateThreadData
	{
		CClient *pClients;
		CConfig *pConfig;
		LOCK *pLock;
		volatile short m_ReloadRequired;
	} m_JSONUpdateThreadData;

	static void JSONUpdateThread(void *pUser);
public:
	CMain(CConfig Config);

	void OnNewClient(int ClienNettID, int ClientID);
	void OnDelClient(int ClientNetID);
	int HandleMessage(int ClientNetID, char *pMessage);
	int ReadConfig();
	int Run();

	CClient *Client(int ClientID) { return &m_aClients[ClientID]; }
	CClient *ClientNet(int ClientNetID);
	const CConfig *Config() const { return &m_Config; }
	int ClientNetToClient(int ClientNetID);
};


#endif
