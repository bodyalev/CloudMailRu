unit Settings;

interface

uses Classes, Windows, SysUtils, IniFiles, System.Variants, Plugin_Types, AskPassword, MRC_Helper, controls;

const
	ProxyNone = 0;
	ProxySocks5 = 1;
	ProxySocks4 = 2;
	ProxyHTTP = 3;

	SocksProxyTypes = [ProxySocks5, ProxySocks4];

type

	TAccountSettings = record
		name, email, password: WideString;
		use_tc_password_manager, twostep_auth: boolean;
		user, domain: WideString; // parsed values from email
		unlimited_filesize: boolean;
		split_large_files: boolean;
	end;

	TProxySettings = record
		ProxyType: Integer;
		Server: WideString;
		Port: Integer;
		user: WideString;
		password: WideString;
		use_tc_password_manager: boolean;
	end;

	TPluginSettings = record
		IniPath: Integer;
		LoadSSLDLLOnlyFromPluginDir: boolean;
		PreserveFileTime: boolean;
		DescriptionEnabled: boolean;
		OperationsViaPublicLinkEnabled: boolean;
		AskOnErrors: boolean;
		SocketTimeout: Integer;
		Proxy: TProxySettings;
	end;

function GetProxyPasswordNow(var ProxySettings: TProxySettings; MyLogProc: TLogProcW; MyCryptProc: TCryptProcW; PluginNum: Integer; CryptoNum: Integer): boolean;
function GetPluginSettings(IniFilePath: WideString): TPluginSettings;
procedure SetPluginSettings(IniFilePath: WideString; PluginSettings: TPluginSettings);
procedure SetPluginSettingsValue(IniFilePath: WideString; OptionName: WideString; OptionValue: Variant);
function GetAccountSettingsFromIniFile(IniFilePath: WideString; AccountName: WideString): TAccountSettings;
function SetAccountSettingsToIniFile(IniFilePath: WideString; AccountSettings: TAccountSettings): boolean;
procedure GetAccountsListFromIniFile(IniFilePath: WideString; var AccountsList: TStringList);
procedure DeleteAccountFromIniFile(IniFilePath: WideString; AccountName: WideString);

implementation

function GetProxyPasswordNow(var ProxySettings: TProxySettings; MyLogProc: TLogProcW; MyCryptProc: TCryptProcW; PluginNum: Integer; CryptoNum: Integer): boolean;
var
	CryptResult: Integer;
	AskResult: Integer;
	TmpString: WideString;
	buf: PWideChar;
begin
	if (ProxySettings.ProxyType = ProxyNone) or (ProxySettings.user = '') then exit(true); // no username means no password required

	if ProxySettings.use_tc_password_manager then
	begin // ������ ������ ������� �� TC
		GetMem(buf, 1024);
		CryptResult := MyCryptProc(PluginNum, CryptoNum, FS_CRYPT_LOAD_PASSWORD_NO_UI, PWideChar('proxy' + ProxySettings.user), buf, 1024); // �������� ����� ������ ��-������
		if CryptResult = FS_FILE_NOTFOUND then
		begin
			MyLogProc(PluginNum, msgtype_details, PWideChar('No master password entered yet'));
			CryptResult := MyCryptProc(PluginNum, CryptoNum, FS_CRYPT_LOAD_PASSWORD, PWideChar('proxy' + ProxySettings.user), buf, 1024);
		end;
		if CryptResult = FS_FILE_OK then // ������� �������� ������
		begin
			ProxySettings.password := buf;
			// Result := true;
		end;
		if CryptResult = FS_FILE_NOTSUPPORTED then // ������������ ������� ���� �������� ������
		begin
			MyLogProc(PluginNum, msgtype_importanterror, PWideChar('CryptProc returns error: Decrypt failed'));
		end;
		if CryptResult = FS_FILE_READERROR then
		begin
			MyLogProc(PluginNum, msgtype_importanterror, PWideChar('CryptProc returns error: Password not found in password store'));
		end;
		FreeMemory(buf);
	end; // else // ������ �� ������, ������ ��� ������ ���� � ���������� (���� � �������� ���� �� ��������)

	if ProxySettings.password = '' then // �� ������ ���, �� � ��������, �� � ������
	begin
		AskResult := TAskPasswordForm.AskPassword(FindTCWindow, 'User ' + ProxySettings.user + ' proxy', ProxySettings.password, ProxySettings.use_tc_password_manager);
		if AskResult <> mrOK then
		begin // �� ������� ������ � �������
			exit(false); // ���������� ������� ������
		end else begin
			if ProxySettings.use_tc_password_manager then
			begin
				case MyCryptProc(PluginNum, CryptoNum, FS_CRYPT_SAVE_PASSWORD, PWideChar('proxy' + ProxySettings.user), PWideChar(ProxySettings.password), SizeOf(ProxySettings.password)) of
					FS_FILE_OK:
						begin // TC ������ ������, �������� � ������� �������
							MyLogProc(PluginNum, msgtype_details, PWideChar('Password saved in TC password manager'));
							TmpString := ProxySettings.password;
							ProxySettings.password := '';
							ProxySettings.use_tc_password_manager := true; // �� ������ ���������!
							ProxySettings.password := TmpString;
						end;
					FS_FILE_NOTSUPPORTED: // ���������� �� ����������
						begin
							MyLogProc(PluginNum, msgtype_importanterror, PWideChar('CryptProc returns error: Encrypt failed'));
						end;
					FS_FILE_WRITEERROR: // ���������� ����� �� ����������
						begin
							MyLogProc(PluginNum, msgtype_importanterror, PWideChar('Password NOT saved: Could not write password to password store'));
						end;
					FS_FILE_NOTFOUND: // �� ������ ������-������
						begin
							MyLogProc(PluginNum, msgtype_importanterror, PWideChar('Password NOT saved: No master password entered yet'));
						end;
					// ������ ����� �� ������, ��� ������ �� �� �������� - �� ����� ���� ����� � �������
				end;
			end;
			result := true;
		end;
	end
	else result := true; // ������ ���� �� �������� ��������
end;

function GetPluginSettings(IniFilePath: WideString): TPluginSettings;
var
	IniFile: TIniFile;
begin
	IniFile := TIniFile.Create(IniFilePath);
	GetPluginSettings.IniPath := IniFile.ReadInteger('Main', 'IniPath', 0);
	GetPluginSettings.LoadSSLDLLOnlyFromPluginDir := IniFile.ReadBool('Main', 'LoadSSLDLLOnlyFromPluginDir', false);
	GetPluginSettings.PreserveFileTime := IniFile.ReadBool('Main', 'PreserveFileTime', false);
	GetPluginSettings.DescriptionEnabled := IniFile.ReadBool('Main', 'DescriptionEnabled', false);
	GetPluginSettings.OperationsViaPublicLinkEnabled := IniFile.ReadBool('Main', 'OperationsViaPublicLinkEnabled', false);
	GetPluginSettings.AskOnErrors := IniFile.ReadBool('Main', 'AskOnErrors', false);
	GetPluginSettings.SocketTimeout := IniFile.ReadInteger('Main', 'SocketTimeout', -1);
	GetPluginSettings.Proxy.ProxyType := IniFile.ReadInteger('Main', 'ProxyType', ProxyNone);
	GetPluginSettings.Proxy.Server := IniFile.ReadString('Main', 'ProxyServer', '');
	GetPluginSettings.Proxy.Port := IniFile.ReadInteger('Main', 'ProxyPort', 0);
	GetPluginSettings.Proxy.user := IniFile.ReadString('Main', 'ProxyUser', '');
	GetPluginSettings.Proxy.use_tc_password_manager := IniFile.ReadBool('Main', 'ProxyTCPwdMngr', false);
	GetPluginSettings.Proxy.password := IniFile.ReadString('Main', 'ProxyPassword', '');
	IniFile.Destroy;
end;

procedure SetPluginSettings(IniFilePath: WideString; PluginSettings: TPluginSettings); { �� ������������ }
var
	IniFile: TIniFile;
begin
	IniFile := TIniFile.Create(IniFilePath);
	IniFile.WriteBool('Main', 'LoadSSLDLLOnlyFromPluginDir', PluginSettings.LoadSSLDLLOnlyFromPluginDir);
	IniFile.WriteBool('Main', 'PreserveFileTime', PluginSettings.PreserveFileTime);
	IniFile.Destroy;
end;

procedure SetPluginSettingsValue(IniFilePath: WideString; OptionName: WideString; OptionValue: Variant);
var
	IniFile: TIniFile;
	basicType: Integer;
begin
	basicType := VarType(OptionValue);
	try
		IniFile := TIniFile.Create(IniFilePath);
		case basicType of
			varInteger: IniFile.WriteInteger('Main', OptionName, OptionValue);
			varString, varUString: IniFile.WriteString('Main', OptionName, OptionValue);
			varBoolean: IniFile.WriteBool('Main', OptionName, OptionValue);
		end;
		IniFile.Destroy;
	except
		On E: EIniFileException do
		begin
			MessageBoxW(0, PWideChar(E.Message), 'INI file error', MB_ICONERROR + MB_OK);
			exit;
		end;
	end;

end;

function GetAccountSettingsFromIniFile(IniFilePath: WideString; AccountName: WideString): TAccountSettings;
var
	IniFile: TIniFile;
	AtPos: Integer;
begin
	IniFile := TIniFile.Create(IniFilePath);
	result.name := AccountName;
	result.email := IniFile.ReadString(result.name, 'email', '');
	result.password := IniFile.ReadString(result.name, 'password', '');
	result.use_tc_password_manager := IniFile.ReadBool(result.name, 'tc_pwd_mngr', false);
	result.unlimited_filesize := IniFile.ReadBool(result.name, 'unlimited_filesize', false);
	result.split_large_files := IniFile.ReadBool(result.name, 'split_large_files', false);
	result.twostep_auth := IniFile.ReadBool(result.name, 'twostep_auth', false);
	AtPos := AnsiPos('@', result.email);
	if AtPos <> 0 then
	begin
		result.user := Copy(result.email, 0, AtPos - 1);
		result.domain := Copy(result.email, AtPos + 1, Length(result.email) - Length(result.user) + 1);
	end;
	IniFile.Destroy;
end;

function SetAccountSettingsToIniFile(IniFilePath: WideString; AccountSettings: TAccountSettings): boolean;
var
	IniFile: TIniFile;
begin
	result := false;
	if AccountSettings.name <> '' then result := true;
	IniFile := TIniFile.Create(IniFilePath);
	IniFile.WriteString(AccountSettings.name, 'email', AccountSettings.email);
	IniFile.WriteString(AccountSettings.name, 'password', AccountSettings.password);
	IniFile.WriteBool(AccountSettings.name, 'tc_pwd_mngr', AccountSettings.use_tc_password_manager);
	IniFile.WriteBool(AccountSettings.name, 'unlimited_filesize', AccountSettings.unlimited_filesize);
	IniFile.WriteBool(AccountSettings.name, 'split_large_files', AccountSettings.split_large_files);
	IniFile.WriteBool(AccountSettings.name, 'twostep_auth', AccountSettings.twostep_auth);
	IniFile.Destroy;
end;

procedure GetAccountsListFromIniFile(IniFilePath: WideString; var AccountsList: TStringList);
var
	IniFile: TIniFile;
begin
	IniFile := TIniFile.Create(IniFilePath);
	IniFile.ReadSections(AccountsList);
	IniFile.Destroy;
end;

procedure DeleteAccountFromIniFile(IniFilePath: WideString; AccountName: WideString);
var
	IniFile: TIniFile;
begin
	IniFile := TIniFile.Create(IniFilePath);
	IniFile.EraseSection(AccountName);
	IniFile.Destroy;
end;

end.
