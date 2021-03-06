﻿unit CloudMailRu;

interface

uses System.Classes, System.SysUtils, PLUGIN_Types, JSON, Winapi.Windows, IdStack, MRC_helper, Settings, IdCookieManager, IdIOHandler, IdIOHandlerSocket, IdIOHandlerStack, IdSSL, IdSSLOpenSSL, IdBaseComponent, IdComponent, IdTCPConnection, IdTCPClient, IdSocks, IdHTTP, IdAuthentication, IdIOHandlerStream, IdMultipartFormData, FileSplitter;

const
{$IFDEF WIN64}
	PlatformX = 'x64';
{$ENDIF}
{$IFDEF WIN32}
	PlatformX = 'x32';
{$ENDIF}
	TYPE_DIR = 'folder';
	TYPE_FILE = 'file';
	{Константы для обозначения ошибок, возвращаемых при парсинге ответов облака. Дополняем по мере обнаружения}
	CLOUD_ERROR_UNKNOWN = -2; //unknown: 'Ошибка на сервере'
	CLOUD_OPERATION_ERROR_STATUS_UNKNOWN = -1;
	CLOUD_OPERATION_OK = 0;
	CLOUD_OPERATION_FAILED = 1;
	CLOUD_OPERATION_CANCELLED = 5;

	CLOUD_ERROR_EXISTS = 1; //exists: 'Папка с таким названием уже существует. Попробуйте другое название'
	CLOUD_ERROR_REQUIRED = 2; //required: 'Название папки не может быть пустым'
	CLOUD_ERROR_INVALID = 3; //invalid: '&laquo;' + app.escapeHTML(name) + '&raquo; это неправильное название папки. В названии папок нельзя использовать символы «" * / : < > ?  \\ |»'
	CLOUD_ERROR_READONLY = 4; //readonly|read_only: 'Невозможно создать. Доступ только для просмотра'
	CLOUD_ERROR_NAME_LENGTH_EXCEEDED = 5; //name_length_exceeded: 'Ошибка: Превышена длина имени папки. <a href="https://help.mail.ru/cloud_web/confines" target="_blank">Подробнее…</a>'
	CLOUD_ERROR_OVERQUOTA = 7; //overquota: 'Невозможно скопировать, в вашем Облаке недостаточно места'
	CLOUD_ERROR_QUOTA_EXCEEDED = 7; //"quota_exceeded": 'Невозможно скопировать, в вашем Облаке недостаточно места'
	CLOUD_ERROR_NOT_EXISTS = 8; //"not_exists": 'Копируемая ссылка не существует'
	CLOUD_ERROR_OWN = 9; //"own": 'Невозможно клонировать собственную ссылку'
	CLOUD_ERROR_NAME_TOO_LONG = 10; //"name_too_long": 'Превышен размер имени файла'

	{Режимы работы при конфликтах копирования}
	CLOUD_CONFLICT_STRICT = 'strict'; //возвращаем ошибку при существовании файла
	CLOUD_CONFLICT_IGNORE = 'ignore'; //В API, видимо, не реализовано
	CLOUD_CONFLICT_RENAME = 'rename'; //Переименуем новый файл
	//CLOUD_CONFLICT_REPLACE = 'overwrite'; // хз, этот ключ не вскрыт

	CLOUD_MAX_FILESIZE = 2000000000; //2Gb, not $80000000 => 2Gib

	CLOUD_MAX_NAME_LENGTH = 255;
	CLOUD_PUBLISH = true;
	CLOUD_UNPUBLISH = false;

	{Поддерживаемые методы авторизации}
	CLOUD_AUTH_METHOD_WEB = 0; //Через парсинг HTTP-страницы
	CLOUD_AUTH_METHOD_OAUTH = 1; //Через сервер OAuth-авторизации

type
	TCloudMailRuDirListingItem = Record
		tree: WideString;
		name: WideString;
		grev: integer;
		size: int64;
		kind: WideString;
		weblink: WideString;
		rev: integer;
		type_: WideString;
		home: WideString;
		mtime: int64;
		hash: WideString;
		virus_scan: WideString;
		folders_count: integer;
		files_count: integer;
	End;

	TCloudMailRuOAuthInfo = Record
		error: WideString;
		error_code: integer;
		error_description: WideString;
		expires_in: integer;
		refresh_token: WideString;
		access_token: WideString;
	end;

	TCloudMailRuSpaceInfo = record
		overquota: Boolean;
		total: int64;
		used: int64;
	End;

	TCloudMailRuDirListing = array of TCloudMailRuDirListingItem;

	TCloudMailRu = class
	private
		domain: WideString;
		user: WideString;
		password: WideString;
		unlimited_filesize: Boolean;
		split_large_files: Boolean;
		token: WideString;
		OAuthToken: TCloudMailRuOAuthInfo;
		x_page_id: WideString;
		build: WideString;
		upload_url: WideString;
		Cookie: TIdCookieManager;
		Socks: TIdSocksInfo;

		ExternalProgressProc: TProgressProcW;
		ExternalLogProc: TLogProcW;

		Shard: WideString;
		login_method: integer;

		Proxy: TProxySettings;

		ConnectTimeout: integer;

		function getToken(): Boolean;
		function getOAuthToken(var OAuthToken: TCloudMailRuOAuthInfo): Boolean;
		function getShard(var Shard: WideString): Boolean;
		function putFileToCloud(localPath: WideString; Return: TStringList): integer;
		function addFileToCloud(hash: WideString; size: int64; remotePath: WideString; var JSONAnswer: WideString; ConflictMode: WideString = CLOUD_CONFLICT_STRICT): Boolean;
		function getUserSpace(var SpaceInfo: TCloudMailRuSpaceInfo): Boolean;
		function HTTPPost(URL: WideString; PostData: TStringStream; var Answer: WideString; ContentType: WideString = 'application/x-www-form-urlencoded'): Boolean; //Постинг данных с возможным получением ответа.

		function HTTPPostFile(URL: WideString; PostData: TIdMultipartFormDataStream; var Answer: WideString): integer; //Постинг файла и получение ответа
		function HTTPGetFile(URL: WideString; var FileStream: TFileStream; LogErrors: Boolean = true): integer;
		function HTTPGet(URL: WideString; var Answer: WideString; var ProgressEnabled: Boolean): Boolean; //если ProgressEnabled - включаем обработчик onWork, возвращаем ProgressEnabled=false при отмене
		function getTokenFromText(Text: WideString): WideString;
		function get_x_page_id_FromText(Text: WideString): WideString;
		function get_build_FromText(Text: WideString): WideString;
		function get_upload_url_FromText(Text: WideString): WideString;
		function getDirListingFromJSON(JSON: WideString): TCloudMailRuDirListing;
		function getUserSpaceFromJSON(JSON: WideString): TCloudMailRuSpaceInfo;
		function getFileStatusFromJSON(JSON: WideString): TCloudMailRuDirListingItem;
		function getShardFromJSON(JSON: WideString): WideString;
		function getOAuthTokenInfoFromJson(JSON: WideString): TCloudMailRuOAuthInfo;
		function getPublicLinkFromJSON(JSON: WideString): WideString;
		function getOperationResultFromJSON(JSON: WideString; var OperationStatus: integer): integer;
		procedure HttpProgress(ASender: TObject; AWorkMode: TWorkMode; AWorkCount: int64);
		procedure Log(MsgType: integer; LogString: WideString);
		function getErrorText(ErrorCode: integer): WideString;
	protected
		procedure HTTPInit(var HTTP: TIdHTTP; var SSL: TIdSSLIOHandlerSocketOpenSSL; var Socks: TIdSocksInfo; var Cookie: TIdCookieManager);
		procedure HTTPDestroy(var HTTP: TIdHTTP; var SSL: TIdSSLIOHandlerSocketOpenSSL);
	public
		ExternalPluginNr: integer;
		ExternalSourceName: PWideChar;
		ExternalTargetName: PWideChar;
		constructor Create(user, domain, password: WideString; unlimited_filesize: Boolean; split_large_files: Boolean; Proxy: TProxySettings; ConnectTimeout: integer; ExternalProgressProc: TProgressProcW = nil; PluginNr: integer = -1; ExternalLogProc: TLogProcW = nil);
		destructor Destroy; override;
		function login(method: integer = CLOUD_AUTH_METHOD_WEB): Boolean;

		procedure logUserSpaceInfo();
		function getDescriptionFile(remotePath, localCopy: WideString): integer; //Если в каталоге remotePath есть descript.ion - скопировать его в файл localcopy
		function getDir(path: WideString; var DirListing: TCloudMailRuDirListing): Boolean;
		function getFile(remotePath, localPath: WideString; LogErrors: Boolean = true): integer; //LogErrors=false => не логируем результат копирования, нужно для запроса descript.ion (которого может не быть)
		function putFile(localPath, remotePath: WideString; ConflictMode: WideString = CLOUD_CONFLICT_STRICT): integer;
		function deleteFile(path: WideString): Boolean;
		function createDir(path: WideString): Boolean;
		function removeDir(path: WideString): Boolean;
		function renameFile(OldName, NewName: WideString): integer; //смена имени без перемещения
		function moveFile(OldName, ToPath: WideString): integer; //перемещение по дереву каталогов
		function copyFile(OldName, ToPath: WideString): integer; //Копирование файла внутри одного каталога
		function mvFile(OldName, NewName: WideString): integer; //объединяющая функция, определяет делать rename или move
		function cpFile(OldName, NewName: WideString): integer; //Копирует файл, и переименует, если нужно
		function publishFile(path: WideString; var PublicLink: WideString; publish: Boolean = CLOUD_PUBLISH): Boolean;
		function statusFile(path: WideString; var FileInfo: TCloudMailRuDirListingItem): Boolean;
		function cloneWeblink(path, link: WideString; ConflictMode: WideString = CLOUD_CONFLICT_RENAME): integer; //клонировать публичную ссылку в текущий каталог

	end;

implementation

{TCloudMailRu}

{CONSTRUCTOR/DESTRUCTOR}

constructor TCloudMailRu.Create(user, domain, password: WideString; unlimited_filesize: Boolean; split_large_files: Boolean; Proxy: TProxySettings; ConnectTimeout: integer; ExternalProgressProc: TProgressProcW; PluginNr: integer; ExternalLogProc: TLogProcW);
begin
	try
		self.Cookie := TIdCookieManager.Create();
		self.Proxy := Proxy;
		if Proxy.ProxyType in SocksProxyTypes then //SOCKS proxy initialization
		begin
			self.Socks := TIdSocksInfo.Create();
			self.Socks.Host := Proxy.Server;
			self.Socks.Port := Proxy.Port;
			if Proxy.user <> '' then
			begin
				self.Socks.Authentication := saUsernamePassword;
				self.Socks.Username := Proxy.user;
				self.Socks.password := Proxy.password;
			end
			else self.Socks.Authentication := saNoAuthentication;

			case Proxy.ProxyType of
				ProxySocks5:
					begin
						Socks.Version := svSocks5;
					end;
				ProxySocks4:
					begin
						Socks.Version := svSocks4;
					end;
			end;
			self.Socks.Enabled := true;
		end;

		self.user := user;
		self.password := password;
		self.domain := domain;
		self.unlimited_filesize := unlimited_filesize;
		self.split_large_files := split_large_files;
		self.ConnectTimeout := ConnectTimeout;
		self.ExternalProgressProc := ExternalProgressProc;
		self.ExternalLogProc := ExternalLogProc;

		self.ExternalPluginNr := PluginNr;
		self.ExternalSourceName := '';
		self.ExternalTargetName := '';
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Cloud initialization error: ' + E.Message);
		end;

	end;

end;

destructor TCloudMailRu.Destroy;
begin
	if Assigned(self.Cookie) then self.Cookie.free;
	if Assigned(self.Socks) then self.Socks.free;
end;

{PRIVATE METHODS}

function TCloudMailRu.getToken(): Boolean;
var
	URL: WideString;
	JSON: WideString;
	Progress: Boolean;
begin
	URL := 'https://cloud.mail.ru/?from=promo&from=authpopup';
	Result := false;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	try
		Progress := false;
		Result := self.HTTPGet(URL, JSON, Progress);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Get token error: ' + E.Message);
		end;
	end;

	if Result then
	begin
		self.token := self.getTokenFromText(JSON);
		self.x_page_id := self.get_x_page_id_FromText(JSON);
		self.build := self.get_build_FromText(JSON);
		self.upload_url := self.get_upload_url_FromText(JSON);
		if (self.token = '') or (self.x_page_id = '') or (self.build = '') or (self.upload_url = '') then Result := false; //В полученной странице нет нужных данных
	end;
end;

function TCloudMailRu.getOAuthToken(var OAuthToken: TCloudMailRuOAuthInfo): Boolean;
var
	URL: WideString;
	Answer: WideString;
	PostData: TStringStream;
	SuccessPost: Boolean;
begin
	SuccessPost := false;
	Result := false;
	URL := 'https://o2.mail.ru/token';
	PostData := TStringStream.Create('client_id=cloud-win&grant_type=password&username=' + self.user + '%40' + self.domain + '&password=' + UrlEncode(self.password), TEncoding.UTF8);
	try
		SuccessPost := self.HTTPPost(URL, PostData, Answer);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Get OAuth token error: ' + E.Message);
			PostData.free;
		end;
	end;
	if SuccessPost then
	begin
		OAuthToken := self.getOAuthTokenInfoFromJson(Answer);
		Result := OAuthToken.error_code = NOERROR;
	end;
	PostData.free;
end;

function TCloudMailRu.getShard(var Shard: WideString): Boolean;
var
	URL: WideString;
	PostData: TStringStream;
	JSON: WideString;
	SuccessPost: Boolean;
	OperationResult, OperationStatus: integer;
begin
	Result := false;
	SuccessPost := false;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	URL := 'https://cloud.mail.ru/api/v2/dispatcher/';
	PostData := TStringStream.Create('api=2&build=' + self.build + '&email=' + self.user + '%40' + self.domain + '&token=' + self.token + '&x-email=' + self.user + '%40' + self.domain + '&x-page-id=' + self.x_page_id, TEncoding.UTF8);
	try
		SuccessPost := self.HTTPPost(URL, PostData, JSON);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Get shard error: ' + E.Message);
			PostData.free;
		end;
	end;
	PostData.free;
	if SuccessPost then
	begin
		OperationResult := self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					Shard := self.getShardFromJSON(JSON);
					Result:=Shard <> '';
				end;
			else
				begin
					Result := false;
					Log(MSGTYPE_IMPORTANTERROR, 'Get shard error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
				end;
		end;
	end;
end;

function TCloudMailRu.putFileToCloud(localPath: WideString; Return: TStringList): integer; {Заливка на сервер состоит из двух шагов: заливаем файл на сервер в putFileToCloud и добавляем его в облако addFileToCloud}
var
	URL, PostAnswer: WideString;
	PostData: TIdMultipartFormDataStream;
begin
	Result := CLOUD_OPERATION_FAILED;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	URL := self.upload_url + '/?cloud_domain=1&x-email=' + self.user + '%40' + self.domain + '&fileapi' + DateTimeToUnix(now).ToString + '0246';
	//Log( MSGTYPE_DETAILS, 'Uploading to ' + URL);
	PostData := TIdMultipartFormDataStream.Create;
	try
		PostData.AddFile('file', GetUNCFilePath(localPath), 'application/octet-stream');
		Result := self.HTTPPostFile(URL, PostData, PostAnswer);
	except
		on E: Exception do //todo проверь, нужны ли эти исключения
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Posting file error: ' + E.Message);
		end;
	end;
	PostData.free;
	if (Result = CLOUD_OPERATION_OK) then
	begin
		ExtractStrings([';'], [], PWideChar(PostAnswer), Return);
		if Length(Return.Strings[0]) <> 40 then //? добавить анализ ответа?
		begin
			Result := CLOUD_OPERATION_FAILED;
		end
	end;
end;

function TCloudMailRu.addFileToCloud(hash: WideString; size: int64; remotePath: WideString; var JSONAnswer: WideString; ConflictMode: WideString = CLOUD_CONFLICT_STRICT): Boolean;
var
	URL: WideString;
	PostData: TStringStream;
begin
	Result := false;
	URL := 'https://cloud.mail.ru/api/v2/file/add';
	PostData := TStringStream.Create('conflict=' + ConflictMode + '&home=/' + remotePath + '&hash=' + hash + '&size=' + size.ToString + '&token=' + self.token + '&build=' + self.build + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&x-page-id=' + self.x_page_id + '&conflict', TEncoding.UTF8);
	{Экспериментально выяснено, что параметры api, build, email, x-email, x-page-id в запросе не обязательны}
	try
		Result := self.HTTPPost(URL, PostData, JSONAnswer);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Adding file error: ' + E.Message);
			PostData.free;
		end;
	end;
	PostData.free;
end;

function TCloudMailRu.getUserSpace(var SpaceInfo: TCloudMailRuSpaceInfo): Boolean;
var
	URL: WideString;
	JSON: WideString;
	Progress: Boolean;
	OperationResult, OperationStatus: integer;
begin
	Result := false;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	URL := 'https://cloud.mail.ru/api/v2/user/space?api=2&home=/&build=' + self.build + '&x-page-id=' + self.x_page_id + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&token=' + self.token + '&_=1433249148810';
	try
		Progress := false;
		Result := self.HTTPGet(URL, JSON, Progress);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'User space receiving error: ' + E.Message);
		end;
	end;

	if Result then
	begin
		OperationResult := self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					Result := true;
					SpaceInfo := self.getUserSpaceFromJSON(JSON);
				end;
			else
				begin
					Result := false;
					Log(MSGTYPE_IMPORTANTERROR, 'User space receiving error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
				end;
		end;
	end;
end;

function TCloudMailRu.HTTPPost(URL: WideString; PostData: TStringStream; var Answer: WideString; ContentType: WideString = 'application/x-www-form-urlencoded'): Boolean;
var
	MemStream: TStringStream;
	HTTP: TIdHTTP;
	SSL: TIdSSLIOHandlerSocketOpenSSL;
	Socks: TIdSocksInfo;
begin
	Result := true;
	MemStream := TStringStream.Create;
	try
		self.HTTPInit(HTTP, SSL, Socks, self.Cookie);
		if ContentType <> '' then HTTP.Request.ContentType := ContentType;
		HTTP.Post(URL, PostData, MemStream);
		self.HTTPDestroy(HTTP, SSL);
		Answer := MemStream.DataString;
	except
		on E: EAbort do
		begin
			exit(false);
		end;
		on E: EIdHTTPProtocolException do
		begin
			if HTTP.ResponseCode = 400 then
			begin {сервер вернёт 400, но нужно пропарсить результат для дальнейшего определения действий}
				Answer := E.ErrorMessage;
				Result := true;
			end else if HTTP.ResponseCode = 507 then //кончилось место
			begin
				Answer := E.ErrorMessage;
				Result := true;
				//end else if (HTTP.ResponseCode = 500) then // Внезапно, сервер так отвечает, если при перемещении файл уже существует, но полагаться на это мы не можем
				//begin

			end else begin
				Log(MSGTYPE_IMPORTANTERROR, E.ClassName + ' ошибка с сообщением: ' + E.Message + ' при отправке данных на адрес ' + URL + ', ответ сервера: ' + E.ErrorMessage);
				Result := false;
			end;
		end;
		on E: EIdSocketerror do
		begin
			Log(MSGTYPE_IMPORTANTERROR, E.ClassName + ' ошибка сети: ' + E.Message + ' при отправке данных на адрес ' + URL);
			Result := false;
		end;
	end;
	MemStream.free;
end;

function TCloudMailRu.HTTPPostFile(URL: WideString; PostData: TIdMultipartFormDataStream; var Answer: WideString): integer;
var
	MemStream: TStringStream;
	HTTP: TIdHTTP;
	SSL: TIdSSLIOHandlerSocketOpenSSL;
	Socks: TIdSocksInfo;
begin
	Result := CLOUD_OPERATION_OK;
	MemStream := TStringStream.Create;
	try
		self.HTTPInit(HTTP, SSL, Socks, self.Cookie);
		HTTP.OnWork := self.HttpProgress;
		HTTP.Post(URL, PostData, MemStream);
		Answer := MemStream.DataString;
		self.HTTPDestroy(HTTP, SSL);
	except
		on E: EAbort do
		begin
			Result := CLOUD_OPERATION_CANCELLED;
		end;
		on E: EIdHTTPProtocolException do
		begin
			Log(MSGTYPE_IMPORTANTERROR, E.ClassName + ' ошибка с сообщением: ' + E.Message + ' при отправке данных на адрес ' + URL + ', ответ сервера: ' + E.ErrorMessage);
			Result := CLOUD_OPERATION_FAILED;
		end;
		on E: EIdSocketerror do
		begin
			Log(MSGTYPE_IMPORTANTERROR, E.ClassName + ' ошибка сети: ' + E.Message + ' при отправке данных на адрес ' + URL);
			Result := CLOUD_OPERATION_FAILED;
		end;
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, E.ClassName + ' ошибка с сообщением: ' + E.Message + ' при отправке данных на адрес ' + URL);
			Result := CLOUD_OPERATION_FAILED;
		end;
	end;
	MemStream.free
end;

function TCloudMailRu.HTTPGet(URL: WideString; var Answer: WideString; var ProgressEnabled: Boolean): Boolean;
var
	HTTP: TIdHTTP;
	SSL: TIdSSLIOHandlerSocketOpenSSL;
	Socks: TIdSocksInfo;
begin
	try
		self.HTTPInit(HTTP, SSL, Socks, self.Cookie);
		if ProgressEnabled then //Вызов прогресса ведёт к возможности отменить получение списка каталогов и других операций, поэтому он нужен не всегда
		begin
			HTTP.OnWork := self.HttpProgress;
		end;

		Answer := HTTP.Get(URL);
		self.HTTPDestroy(HTTP, SSL);
	Except
		on E: EAbort do
		begin
			Answer := E.Message;
			ProgressEnabled := false; //сообщаем об отмене
			exit(false);
		end;
		on E: EIdHTTPProtocolException do
		begin
			if HTTP.ResponseCode = 400 then
			begin {сервер вернёт 400, но нужно пропарсить результат для дальнейшего определения действий}
				Answer := E.ErrorMessage;
				exit(true);
			end else if HTTP.ResponseCode = 507 then //кончилось место
			begin
				Answer := E.ErrorMessage;
				exit(true);
			end else begin
				Log(MSGTYPE_IMPORTANTERROR, E.ClassName + ' ошибка с сообщением: ' + E.Message + ' при отправке данных на адрес ' + URL + ', ответ сервера: ' + E.ErrorMessage);
				exit(false);
			end;
		end;
		on E: EIdSocketerror do
		begin
			Log(MSGTYPE_IMPORTANTERROR, E.ClassName + ' ошибка сети: ' + E.Message + ' при запросе данных с адреса ' + URL);
			exit(false);
		end;
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, E.ClassName + ' ошибка с сообщением: ' + E.Message + ' при запросе данных с адреса ' + URL);
			exit(false);
		end;
	end;
	Result := Answer <> '';
end;

function TCloudMailRu.HTTPGetFile(URL: WideString; var FileStream: TFileStream; LogErrors: Boolean = true): integer;
var
	HTTP: TIdHTTP;
	SSL: TIdSSLIOHandlerSocketOpenSSL;
	Socks: TIdSocksInfo;
begin
	Result := FS_FILE_OK;
	try
		self.HTTPInit(HTTP, SSL, Socks, self.Cookie);
		HTTP.Request.ContentType := 'application/octet-stream';
		HTTP.Response.KeepAlive := true;
		HTTP.OnWork := self.HttpProgress;
		HTTP.Get(URL, FileStream);
		if (HTTP.RedirectCount = HTTP.RedirectMaximum) and (FileStream.size = 0) then
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Достигнуто максимальное количество перенаправлений при запросе файла с адреса ' + URL);
			Result := FS_FILE_READERROR;
		end;
		self.HTTPDestroy(HTTP, SSL);

	except
		on E: EAbort do
		begin
			Result := FS_FILE_USERABORT;
		end;
		on E: EIdSocketerror do
		begin
			if LogErrors then Log(MSGTYPE_IMPORTANTERROR, E.ClassName + ' ошибка сети: ' + E.Message + ' при копировании файла с адреса ' + URL);
			Result := FS_FILE_READERROR;
		end;
		on E: Exception do
		begin
			if LogErrors then Log(MSGTYPE_IMPORTANTERROR, E.ClassName + ' ошибка с сообщением: ' + E.Message + ' при копировании файла с адреса ' + URL);
			Result := FS_FILE_READERROR;
		end;
	end;
end;

procedure TCloudMailRu.HTTPInit(var HTTP: TIdHTTP; var SSL: TIdSSLIOHandlerSocketOpenSSL; var Socks: TIdSocksInfo; var Cookie: TIdCookieManager);
begin
	SSL := TIdSSLIOHandlerSocketOpenSSL.Create();
	HTTP := TIdHTTP.Create();

	if (self.Proxy.ProxyType in SocksProxyTypes) and (self.Socks.Enabled) then SSL.TransparentProxy := self.Socks;

	if self.Proxy.ProxyType = ProxyHTTP then
	begin
		HTTP.ProxyParams.ProxyServer := self.Proxy.Server;
		HTTP.ProxyParams.ProxyPort := self.Proxy.Port;

		if self.Proxy.user <> '' then
		begin
			HTTP.ProxyParams.BasicAuthentication := true;
			HTTP.ProxyParams.ProxyUsername := self.Proxy.user;
			HTTP.ProxyParams.ProxyPassword := self.Proxy.password;
		end

	end;

	HTTP.CookieManager := Cookie;
	HTTP.IOHandler := SSL;

	HTTP.AllowCookies := true;
	HTTP.HTTPOptions := [hoForceEncodeParams, hoNoParseMetaHTTPEquiv];
	HTTP.HandleRedirects := true;
	if (self.ConnectTimeout < 0) then
	begin
		HTTP.ConnectTimeout := self.ConnectTimeout;
		HTTP.ReadTimeout := self.ConnectTimeout;
	end;

	HTTP.Request.UserAgent := 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.17 (KHTML, like Gecko) Chrome/24.0.1312.57 Safari/537.17/TCWFX(' + PlatformX + ')';
end;

procedure TCloudMailRu.HTTPDestroy(var HTTP: TIdHTTP; var SSL: TIdSSLIOHandlerSocketOpenSSL);
begin
	HTTP.free;
	SSL.free;
end;

procedure TCloudMailRu.HttpProgress(ASender: TObject; AWorkMode: TWorkMode; AWorkCount: int64);
var
	HTTP: TIdHTTP;
	ContentLength: int64;
	Percent: integer;
begin
	HTTP := TIdHTTP(ASender);
	if AWorkMode = wmRead then ContentLength := HTTP.Response.ContentLength
	else ContentLength := HTTP.Request.ContentLength; //Считаем размер обработанных данных зависимости от того, скачивание это или загрузка
	if (Pos('chunked', LowerCase(HTTP.Response.TransferEncoding)) = 0) and (ContentLength > 0) then
	begin
		Percent := 100 * AWorkCount div ContentLength;
		if Assigned(ExternalProgressProc) then
		begin
			if ExternalProgressProc(self.ExternalPluginNr, self.ExternalSourceName, self.ExternalTargetName, Percent) = 1 then Abort;
		end;
	end;
end;

procedure TCloudMailRu.Log(MsgType: integer; LogString: WideString);
begin
	if Assigned(ExternalLogProc) then
	begin
		ExternalLogProc(ExternalPluginNr, MsgType, PWideChar(LogString));
	end;
end;

function TCloudMailRu.getErrorText(ErrorCode: integer): WideString;
begin
	case ErrorCode of
		CLOUD_ERROR_EXISTS: exit('Папка с таким названием уже существует. Попробуйте другое название.');
		CLOUD_ERROR_REQUIRED: exit('Название папки не может быть пустым.');
		CLOUD_ERROR_INVALID: exit('Неправильное название папки. В названии папок нельзя использовать символы «" * / : < > ?  \\ |».');
		CLOUD_ERROR_READONLY: exit('Невозможно создать. Доступ только для просмотра.');
		CLOUD_ERROR_NAME_LENGTH_EXCEEDED: exit('Превышена длина имени папки.');
		CLOUD_ERROR_OVERQUOTA: exit('Невозможно скопировать, в вашем Облаке недостаточно места.');
		CLOUD_ERROR_NOT_EXISTS: exit('Копируемая ссылка не существует.');
		CLOUD_ERROR_OWN: exit('Невозможно клонировать собственную ссылку.');
		CLOUD_ERROR_NAME_TOO_LONG: exit('Превышена длина имени файла.');
		else exit('Неизвестная ошибка (' + ErrorCode.ToString + ')');
	end;
end;

{PUBLIC METHODS}

function TCloudMailRu.login(method: integer = CLOUD_AUTH_METHOD_WEB): Boolean;
var
	URL: WideString;
	PostData: TStringStream;
	PostAnswer: WideString; {Не используется}
begin
	Result := false;
	self.login_method := method;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	Log(MSGTYPE_DETAILS, 'Login to ' + self.user + '@' + self.domain);
	case self.login_method of
		CLOUD_AUTH_METHOD_WEB: //todo: вынести в отдельный метод
			begin
				URL := 'https://auth.mail.ru/cgi-bin/auth?lang=ru_RU&from=authpopup';
				PostData := TStringStream.Create('page=https://cloud.mail.ru/?from=promo&new_auth_form=1&Domain=' + self.domain + '&Login=' + self.user + '&Password=' + UrlEncode(self.password) + '&FailPage=', TEncoding.UTF8);
				try
					Result := self.HTTPPost(URL, PostData, PostAnswer);
				except
					on E: Exception do
					begin
						Log(MSGTYPE_IMPORTANTERROR, 'Cloud login error: ' + E.Message);
					end;
				end;
				PostData.free;
				if (Result) then
				begin
					Log(MSGTYPE_DETAILS, 'Requesting auth token for ' + self.user + '@' + self.domain);
					Result := self.getToken();
					if (Result) then
					begin
						Log(MSGTYPE_DETAILS, 'Connected to ' + self.user + '@' + self.domain);
						self.logUserSpaceInfo;
					end else begin
						Log(MSGTYPE_IMPORTANTERROR, 'error: getting auth token for ' + self.user + '@' + self.domain);
						exit(false);
					end;
				end
				else Log(MSGTYPE_IMPORTANTERROR, 'error: login to ' + self.user + '@' + self.domain);
			end;
		CLOUD_AUTH_METHOD_OAUTH:
			begin
				Result := self.getOAuthToken(self.OAuthToken);
				if not Result then
				begin
					Log(MSGTYPE_IMPORTANTERROR, 'OAuth error: ' + self.OAuthToken.error + '(' + self.OAuthToken.error_description + ')');
				end;
			end;
	end;

end;

function TCloudMailRu.deleteFile(path: WideString): Boolean;
var
	URL: WideString;
	PostData: TStringStream;
	JSON: WideString;
	OperationResult, OperationStatus: integer;
begin
	Result := false;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	path := UrlEncode(StringReplace(path, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	URL := 'https://cloud.mail.ru/api/v2/file/remove';
	PostData := TStringStream.Create('api=2&home=/' + path + '&token=' + self.token + '&build=' + self.build + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&x-page-id=' + self.x_page_id + '&conflict', TEncoding.UTF8);
	try
		Result := self.HTTPPost(URL, PostData, JSON);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Delete file error: ' + E.Message);
			Result := false;
		end;
	end;
	PostData.free;
	if Result then
	begin
		OperationResult:= self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					Result := true;
				end;
			else
				begin
					Result := false;
					Log(MSGTYPE_IMPORTANTERROR, 'Delete file error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
				end;
		end;
	end;

end;

procedure TCloudMailRu.logUserSpaceInfo;
var
	US: TCloudMailRuSpaceInfo;
	QuotaInfo: WideString;

	function FormatSize(Megabytes: integer): WideString; //Форматируем размер в удобочитаемый вид
	begin
		if Megabytes > (1024 * 1023) then exit((Megabytes div (1024 * 1024)).ToString() + 'Tb');
		if Megabytes > 1024 then exit((CurrToStrF((Megabytes / 1024), ffNumber, 2)) + 'Gb');
		exit(Megabytes.ToString() + 'Mb');
	end;

begin
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	if self.getUserSpace(US) then
	begin
		if (US.overquota) then QuotaInfo := ' Warning: space quota exhausted!'
		else QuotaInfo := '';

		Log(MSGTYPE_DETAILS, 'Total space: ' + FormatSize(US.total) + ', used: ' + FormatSize(US.used) + ', free: ' + FormatSize(US.total - US.used) + '.' + QuotaInfo);
	end else begin
		Log(MSGTYPE_IMPORTANTERROR, 'error: getting user space information for ' + self.user + '@' + self.domain);
	end;
end;

function TCloudMailRu.getDescriptionFile(remotePath, localCopy: WideString): integer; //0 - ok, else error
begin
	Result := self.getFile(remotePath, localCopy, false);
end;

function TCloudMailRu.getDir(path: WideString; var DirListing: TCloudMailRuDirListing): Boolean;
var
	URL: WideString;
	JSON: WideString;
	Progress: Boolean;
	OperationStatus, OperationResult: integer;
begin
	Result := false;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	URL := 'https://cloud.mail.ru/api/v2/folder?sort={%22type%22%3A%22name%22%2C%22order%22%3A%22asc%22}&offset=0&limit=10000&home=' + UrlEncode(StringReplace(path, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase])) + '&api=2&build=' + self.build + '&x-page-id=' + self.x_page_id + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&token=' + self.token + '&_=1433249148810';
	try
		Progress := false;
		Result := self.HTTPGet(URL, JSON, Progress);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Directory list receiving error: ' + E.Message);
		end;
	end;
	if Result then
	begin
		OperationResult:= self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					DirListing := self.getDirListingFromJSON(JSON);
					Result := true;
				end;
			CLOUD_ERROR_NOT_EXISTS:
				begin
					Log(MSGTYPE_IMPORTANTERROR, 'Path not exists: ' + path);
					Result := false;
				end
			else
				begin
					Log(MSGTYPE_IMPORTANTERROR, 'Delete file error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
					Result := false;
				end;
		end;

	end;
end;

function TCloudMailRu.getFile(remotePath, localPath: WideString; LogErrors: Boolean = true): integer; //0 - ok, else error
var
	FileStream: TFileStream;
begin
	Result := FS_FILE_NOTSUPPORTED;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	if self.Shard = '' then
	begin
		Log(MSGTYPE_DETAILS, 'Current shard is undefined, trying to get one');
		if self.getShard(self.Shard) then
		begin
			Log(MSGTYPE_DETAILS, 'Current shard: ' + self.Shard);
		end else begin //А вот теперь это критическая ошибка, тут уже не получится копировать
			Log(MSGTYPE_IMPORTANTERROR, 'Sorry, downloading impossible');
			exit(FS_FILE_NOTSUPPORTED);
		end;
	end;

	Result := FS_FILE_OK;
	remotePath := UrlEncode(StringReplace(remotePath, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	try
		FileStream := TFileStream.Create(GetUNCFilePath(localPath), fmCreate);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, E.Message);
			exit(FS_FILE_WRITEERROR);
		end;
	end;

	if (Assigned(FileStream)) then
	begin
		try
			Result := self.HTTPGetFile(self.Shard + remotePath, FileStream, LogErrors);
		except
			on E: Exception do
			begin
				if LogErrors then Log(MSGTYPE_IMPORTANTERROR, 'File receiving error: ' + E.Message);
			end;
		end;
		FlushFileBuffers(FileStream.Handle);
		FileStream.free;
	end;

	if Result <> FS_FILE_OK then
	begin
		System.SysUtils.deleteFile(GetUNCFilePath(localPath));
	end;
end;

function TCloudMailRu.publishFile(path: WideString; var PublicLink: WideString; publish: Boolean = CLOUD_PUBLISH): Boolean;
var
	URL: WideString;
	PostData: TStringStream;
	JSON: WideString;
	OperationStatus, OperationResult: integer;
begin
	Result := false;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации

	path := UrlEncode(StringReplace(path, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));

	if publish then
	begin
		URL := 'https://cloud.mail.ru/api/v2/file/publish';
		PostData := TStringStream.Create('api=2&home=/' + path + '&token=' + self.token + '&build=' + self.build + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&x-page-id=' + self.x_page_id + '&conflict', TEncoding.UTF8);
	end else begin
		URL := 'https://cloud.mail.ru/api/v2/file/unpublish';
		PostData := TStringStream.Create('api=2&weblink=' + PublicLink + '&token=' + self.token + '&build=' + self.build + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&x-page-id=' + self.x_page_id + '&conflict', TEncoding.UTF8);
	end;

	try

		Result := self.HTTPPost(URL, PostData, JSON);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'File publish error: ' + E.Message);
		end;
	end;
	PostData.free;

	if Result then
	begin
		OperationResult:= self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					if publish then PublicLink := self.getPublicLinkFromJSON(JSON);
					Result := true;
				end;
			else
				begin
					Result := false;
					Log(MSGTYPE_IMPORTANTERROR, 'File publish error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
				end;
		end;
	end;
end;

function TCloudMailRu.putFile(localPath, remotePath: WideString; ConflictMode: WideString = CLOUD_CONFLICT_STRICT): integer;
var
	PutResult: TStringList;
	JSONAnswer, FileHash: WideString;
	FileSize: int64;
	Code, OperationStatus: integer;
	OperationResult, SplitResult, SplittedPartIndex: integer;
	Splitter: TFileSplitter;
	CRCFileName: WideString;
begin
	if not(Assigned(self)) then exit(FS_FILE_WRITEERROR); //Проверка на вызов без инициализации
	if (not(self.unlimited_filesize)) and (SizeOfFile(GetUNCFilePath(localPath)) >= CLOUD_MAX_FILESIZE + 1) then
	begin
		if self.split_large_files then
		begin
			Log(MSGTYPE_DETAILS, 'File size > ' + CLOUD_MAX_FILESIZE.ToString() + ' bytes, file will be splitted.');
			try
				Splitter := TFileSplitter.Create(localPath, CLOUD_MAX_FILESIZE);
			except
				on E: Exception do
				begin
					Log(MSGTYPE_IMPORTANTERROR, 'File splitting error: ' + E.Message + ', ignored');
					exit(FS_FILE_NOTSUPPORTED);
				end;
			end;
			SplitResult := Splitter.split();
			if SplitResult <> FS_FILE_OK then
			begin
				Log(MSGTYPE_IMPORTANTERROR, 'File splitting error: code: ' + SplitResult.ToString + ', ignored');
				Splitter.Destroy;
				exit(FS_FILE_NOTSUPPORTED);
			end;
			for SplittedPartIndex := 0 to Length(Splitter.SplitResult.parts) - 1 do
			begin
				Result := self.putFile(Splitter.SplitResult.parts[SplittedPartIndex].filename, CopyExt(Splitter.SplitResult.parts[SplittedPartIndex].filename, remotePath), ConflictMode);
				if Result <> FS_FILE_OK then
				begin //Отваливаемся при ошибке
					if Result <> FS_FILE_USERABORT then Log(MSGTYPE_IMPORTANTERROR, 'Partial upload aborted')
					else Log(MSGTYPE_IMPORTANTERROR, 'Partial upload error');
					Splitter.Destroy;
					exit;
				end;
			end;
			CRCFileName := Splitter.writeCRCFile;
			Result := self.putFile(CRCFileName, CopyExt(CRCFileName, remotePath), ConflictMode);
			if Result <> FS_FILE_OK then
			begin //Отваливаемся при ошибке
				if Result <> FS_FILE_USERABORT then Log(MSGTYPE_IMPORTANTERROR, 'Checksum upload aborted')
				else Log(MSGTYPE_IMPORTANTERROR, 'Checksum upload error');
				Splitter.Destroy;
				exit;
			end;
			Splitter.Destroy;
			exit(FS_FILE_OK); //Файлик залит по частям, выходим
		end else begin
			Log(MSGTYPE_IMPORTANTERROR, 'File size > ' + CLOUD_MAX_FILESIZE.ToString() + ' bytes, ignored');
			exit(FS_FILE_NOTSUPPORTED);
		end;

	end;
	FileSize := 0;
	Result := FS_FILE_WRITEERROR;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	OperationResult := CLOUD_OPERATION_FAILED;
	PutResult := TStringList.Create;
	try
		OperationResult := self.putFileToCloud(localPath, PutResult);
	Except
		on E: Exception do
		begin
			if E.ClassName = 'EAbort' then
			begin
				Result := FS_FILE_USERABORT;
			end else begin
				Log(MSGTYPE_IMPORTANTERROR, 'error: uploading to cloud: ' + E.ClassName + ' ошибка с сообщением: ' + E.Message);
				Result := FS_FILE_WRITEERROR;
			end;
		end;
	end;
	if OperationResult = CLOUD_OPERATION_OK then
	begin
		FileHash := PutResult.Strings[0];
		Val(PutResult.Strings[1], FileSize, Code); //Тут ошибка маловероятна
	end else if OperationResult = CLOUD_OPERATION_CANCELLED then
	begin
		Result := FS_FILE_USERABORT;
	end;
	PutResult.free;

	if OperationResult = CLOUD_OPERATION_OK then
	begin
		//Log( MSGTYPE_DETAILS, 'putFileToCloud result: ' + PutResult.Text);
		if self.addFileToCloud(FileHash, FileSize, UrlEncode(StringReplace(remotePath, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase])), JSONAnswer) then
		begin
			OperationResult := self.getOperationResultFromJSON(JSONAnswer, OperationStatus);
			case OperationResult of
				CLOUD_OPERATION_OK:
					begin
						Result := FS_FILE_OK;
					end;
				CLOUD_ERROR_EXISTS:
					begin
						Result := FS_FILE_EXISTS;
					end;
				CLOUD_ERROR_REQUIRED:
					begin
						Result := FS_FILE_WRITEERROR;
					end;
				CLOUD_ERROR_INVALID:
					begin
						Result := FS_FILE_WRITEERROR;
					end;
				CLOUD_ERROR_READONLY:
					begin
						Result := FS_FILE_WRITEERROR;
					end;
				CLOUD_ERROR_NAME_LENGTH_EXCEEDED:
					begin
						Result := FS_FILE_WRITEERROR;
					end;
				CLOUD_ERROR_OVERQUOTA:
					begin
						Log(MSGTYPE_IMPORTANTERROR, 'Insufficient Storage');
						Result := FS_FILE_WRITEERROR;
					end;
				CLOUD_ERROR_NAME_TOO_LONG:
					begin
						Log(MSGTYPE_IMPORTANTERROR, 'Name too long');
						Result := FS_FILE_WRITEERROR;
					end;
				CLOUD_ERROR_UNKNOWN:
					begin
						Result := FS_FILE_NOTSUPPORTED;
					end;
				else
					begin //что-то неизвестное
						Log(MSGTYPE_IMPORTANTERROR, 'Directory creation error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
						Result := FS_FILE_WRITEERROR;
					end;
			end;
		end;
	end;
end;

function TCloudMailRu.createDir(path: WideString): Boolean;
var
	URL: WideString;
	PostData: TStringStream;
	PostAnswer: WideString;
	SucessCreate: Boolean;
	OperationStatus, OperationResult: integer;
begin
	Result := false;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	SucessCreate := false;
	path := UrlEncode(StringReplace(path, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	URL := 'https://cloud.mail.ru/api/v2/folder/add';
	PostData := TStringStream.Create('api=2&home=/' + path + '&token=' + self.token + '&build=' + self.build + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&x-page-id=' + self.x_page_id + '&conflict', TEncoding.UTF8);
	try
		SucessCreate := self.HTTPPost(URL, PostData, PostAnswer);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Directory creation error: ' + E.Message);
		end;
	end;
	PostData.free;
	if SucessCreate then
	begin
		OperationResult :=self.getOperationResultFromJSON(PostAnswer, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					Result := true;
				end;
			else
				begin
					Log(MSGTYPE_IMPORTANTERROR, 'Directory creation error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
					Result := false;
				end;
		end;
	end;
end;

function TCloudMailRu.removeDir(path: WideString): Boolean;
var
	URL: WideString;
	PostData: TStringStream;
	JSON: WideString;
	OperationResult, OperationStatus: integer;
begin
	Result := false;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	path := UrlEncode(StringReplace(path, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	URL := 'https://cloud.mail.ru/api/v2/file/remove';
	PostData := TStringStream.Create('api=2&home=/' + path + '/&token=' + self.token + '&build=' + self.build + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&x-page-id=' + self.x_page_id + '&conflict', TEncoding.UTF8);
	try
		Result := self.HTTPPost(URL, PostData, JSON); //API всегда отвечает true, даже если путь не существует
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Delete directory error: ' + E.Message);
			Result := false;
		end;
	end;
	PostData.free;
	if Result then
	begin
		OperationResult:= self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					Result := true;
				end;
			else
				begin
					Result := false;
					Log(MSGTYPE_IMPORTANTERROR, 'Delete directory error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
				end;
		end;
	end;
end;

function TCloudMailRu.renameFile(OldName, NewName: WideString): integer;
var
	URL: WideString;
	PostData: TStringStream;
	JSON: WideString;
	PostResult: Boolean;
	OperationStatus, OperationResult: integer;
begin
	Result := FS_FILE_WRITEERROR;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	OldName := UrlEncode(StringReplace(OldName, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	NewName := UrlEncode(StringReplace(NewName, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	URL := 'https://cloud.mail.ru/api/v2/file/rename';
	PostResult := false;
	PostData := TStringStream.Create('api=2&home=' + OldName + '&name=' + NewName + '&token=' + self.token + '&build=' + self.build + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&x-page-id=' + self.x_page_id, TEncoding.UTF8);
	try
		PostResult := self.HTTPPost(URL, PostData, JSON);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Rename file error: ' + E.Message);
		end;
	end;
	PostData.free;
	if PostResult then
	begin //Парсим ответ
		OperationResult :=self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					Result := CLOUD_OPERATION_OK
				end;
			CLOUD_ERROR_EXISTS:
				begin
					Result := FS_FILE_EXISTS;
				end;
			CLOUD_ERROR_REQUIRED:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_INVALID:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_READONLY:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_NAME_LENGTH_EXCEEDED:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_UNKNOWN:
				begin
					Result := FS_FILE_NOTSUPPORTED;
				end;
			else
				begin //что-то неизвестное
					Log(MSGTYPE_IMPORTANTERROR, 'Rename file error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
					Result := FS_FILE_WRITEERROR;
				end;
		end;
	end;
end;

function TCloudMailRu.statusFile(path: WideString; var FileInfo: TCloudMailRuDirListingItem): Boolean;
var
	URL: WideString;
	JSON: WideString;
	Progress: Boolean;
	OperationResult, OperationStatus: integer;
begin
	Result := false;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	path := UrlEncode(StringReplace(path, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	URL := 'https://cloud.mail.ru/api/v2/file?home=' + path + '&api=2&build=' + self.build + '&x-page-id=' + self.x_page_id + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&token=' + self.token + '&_=1433249148810';
	try
		Progress := false;
		Result := self.HTTPGet(URL, JSON, Progress);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'File status getting error: ' + E.Message);
		end;
	end;

	if Result then
	begin
		OperationResult := self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					Result := true;
					FileInfo := getFileStatusFromJSON(JSON);
				end;
			else
				begin
					Log(MSGTYPE_IMPORTANTERROR, 'File publish error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
					Result := false;
				end;
		end;
	end;

	if not Result then exit(false);

end;

function TCloudMailRu.cloneWeblink(path, link: WideString; ConflictMode: WideString = CLOUD_CONFLICT_RENAME): integer;
var
	URL: WideString;
	JSON: WideString;
	GetResult: Boolean;
	OperationStatus, OperationResult: integer;
	Progress: Boolean;
begin
	GetResult := false;
	Result := FS_FILE_WRITEERROR;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	path := UrlEncode(StringReplace(path, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	if (path = '') then path := '/'; //preventing error
	URL := 'https://cloud.mail.ru/api/v2/clone?folder=' + path + '&weblink=' + link + '&conflict=' + ConflictMode + '&api=2&build=' + self.build + '&x-page-id=' + self.x_page_id + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&token=' + self.token + '&_=1433249148810';
	try
		Progress := true;
		GetResult := self.HTTPGet(URL, JSON, Progress);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Public link clone error: ' + E.Message);
		end;
	end;
	if GetResult then
	begin //Парсим ответ
		OperationResult := self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					Result := CLOUD_OPERATION_OK
				end;
			CLOUD_ERROR_EXISTS:
				begin
					Result := FS_FILE_EXISTS;
				end;
			CLOUD_ERROR_REQUIRED:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_INVALID:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_READONLY:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_NAME_LENGTH_EXCEEDED:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_UNKNOWN:
				begin
					Result := FS_FILE_NOTSUPPORTED;
				end;
			else
				begin
					Log(MSGTYPE_IMPORTANTERROR, 'File publish error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
					Result := FS_FILE_WRITEERROR;
				end;
		end;
	end else begin //посмотреть это
		if not(Progress) then
		begin //user cancelled
			Result := FS_FILE_USERABORT;
		end else begin //unknown error
			Log(MSGTYPE_IMPORTANTERROR, 'Public link clone error: got ' + OperationStatus.ToString + ' status');
			Result := FS_FILE_WRITEERROR;
		end;

	end;

end;

function TCloudMailRu.copyFile(OldName, ToPath: WideString): integer;
var
	URL: WideString;
	PostData: TStringStream;
	JSON: WideString;
	PostResult: Boolean;
	OperationStatus, OperationResult: integer;
begin
	Result := FS_FILE_WRITEERROR;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	OldName := UrlEncode(StringReplace(OldName, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	ToPath := UrlEncode(StringReplace(ToPath, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	if (ToPath = '') then ToPath := '/'; //preventing error

	URL := 'https://cloud.mail.ru/api/v2/file/copy';
	PostResult := false;
	PostData := TStringStream.Create('api=2&home=' + OldName + '&folder=' + ToPath + '&token=' + self.token + '&build=' + self.build + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&x-page-id=' + self.x_page_id + '&conflict', TEncoding.UTF8);
	try
		PostResult := self.HTTPPost(URL, PostData, JSON);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Copy file error: ' + E.Message);
		end;
	end;
	PostData.free;
	if PostResult then
	begin //Парсим ответ
		OperationResult:=self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					Result := CLOUD_OPERATION_OK
				end;
			CLOUD_ERROR_EXISTS:
				begin
					Result := FS_FILE_EXISTS;
				end;
			CLOUD_ERROR_REQUIRED:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_INVALID:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_READONLY:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_NAME_LENGTH_EXCEEDED:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_UNKNOWN:
				begin
					Result := FS_FILE_NOTSUPPORTED;
				end;
			else
				begin //что-то неизвестное
					Log(MSGTYPE_IMPORTANTERROR, 'File publish error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
					Result := FS_FILE_WRITEERROR;
				end;
		end;
	end;
end;

function TCloudMailRu.moveFile(OldName, ToPath: WideString): integer;
var
	URL: WideString;
	PostData: TStringStream;
	JSON: WideString;
	PostResult: Boolean;
	OperationStatus, OperationResult: integer;
begin
	Result := FS_FILE_WRITEERROR;
	if not(Assigned(self)) then exit; //Проверка на вызов без инициализации
	OldName := UrlEncode(StringReplace(OldName, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	ToPath := UrlEncode(StringReplace(ToPath, WideString('\'), WideString('/'), [rfReplaceAll, rfIgnoreCase]));
	if (ToPath = '') then ToPath := '/'; //preventing error

	URL := 'https://cloud.mail.ru/api/v2/file/move';
	PostResult := false;
	PostData := TStringStream.Create('api=2&home=' + OldName + '&folder=' + ToPath + '&token=' + self.token + '&build=' + self.build + '&email=' + self.user + '%40' + self.domain + '&x-email=' + self.user + '%40' + self.domain + '&x-page-id=' + self.x_page_id + '&conflict', TEncoding.UTF8);
	try
		PostResult := self.HTTPPost(URL, PostData, JSON);
	except
		on E: Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Move file error: ' + E.Message);
		end;
	end;
	PostData.free;
	if PostResult then
	begin //Парсим ответ
		OperationResult:=self.getOperationResultFromJSON(JSON, OperationStatus);
		case OperationResult of
			CLOUD_OPERATION_OK:
				begin
					Result := CLOUD_OPERATION_OK
				end;
			CLOUD_ERROR_EXISTS:
				begin
					Result := FS_FILE_EXISTS;
				end;
			CLOUD_ERROR_REQUIRED:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_INVALID:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_READONLY:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_NAME_LENGTH_EXCEEDED:
				begin
					Result := FS_FILE_WRITEERROR;
				end;
			CLOUD_ERROR_UNKNOWN:
				begin
					Result := FS_FILE_NOTSUPPORTED;
				end;
			else
				begin //что-то неизвестное
					Log(MSGTYPE_IMPORTANTERROR, 'File publish error: ' + self.getErrorText(OperationResult) + ' Status: ' + OperationStatus.ToString());
					Result := FS_FILE_WRITEERROR;
				end;
		end;
	end;
end;

function TCloudMailRu.mvFile(OldName, NewName: WideString): integer;
var
	NewPath: WideString;
	SameDir, SameName: Boolean;
begin //К сожалению, переименование и перемещение в облаке - разные действия
	NewPath := ExtractFilePath(NewName);
	SameDir := ExtractFilePath(OldName) = ExtractFilePath(NewName);
	SameName := ExtractFileName(OldName) = ExtractFileName(NewName);
	if SameDir then
	begin //один каталог
		Result := self.renameFile(OldName, ExtractFileName(NewName));
	end else begin
		Result := self.moveFile(OldName, ExtractFilePath(NewName)); //Если файл со старым именем лежит в новом каталоге, вернётся ошибка. Так реализовано в облаке, а мудрить со временными каталогами я не хочу
		if Result <> CLOUD_OPERATION_OK then exit;
		if not(SameName) then
		begin //скопированный файл лежит в новом каталоге со старым именем
			Result := self.renameFile(NewPath + ExtractFileName(OldName), ExtractFileName(NewName));
		end;
	end;
end;

function TCloudMailRu.cpFile(OldName, NewName: WideString): integer;
var
	NewPath: WideString;
	SameDir, SameName: Boolean;
begin //Облако умеет скопировать файл, но не сможет его переименовать, поэтому хитрим
	NewPath := ExtractFilePath(NewName);
	SameDir := ExtractFilePath(OldName) = ExtractFilePath(NewName);
	SameName := ExtractFileName(OldName) = ExtractFileName(NewName);

	if (SameDir) then //копирование в тот же каталог не поддерживается напрямую, а мудрить со временными каталогами я не хочу
	begin
		Log(MSGTYPE_IMPORTANTERROR, 'Copying in same dir not supported by cloud');
		exit(FS_FILE_NOTSUPPORTED);
	end else begin
		Result := self.copyFile(OldName, NewPath);
		if Result <> CLOUD_OPERATION_OK then exit;
	end;

	if not(SameName) then
	begin //скопированный файл лежит в новом каталоге со старым именем
		Result := self.renameFile(NewPath + ExtractFileName(OldName), ExtractFileName(NewName));
	end;

end;

{PRIVATE STATIC METHODS (kinda)}

function TCloudMailRu.getTokenFromText(Text: WideString): WideString;
var
	start: integer;
begin
	start := Pos(WideString('"csrf"'), Text);
	if start > 0 then
	begin
		getTokenFromText := Copy(Text, start + 8, 32);
	end else begin
		getTokenFromText := '';
	end;
end;

function TCloudMailRu.get_build_FromText(Text: WideString): WideString;
var
	start, finish: integer;
	temp: WideString;
begin
	start := Pos(WideString('"BUILD"'), Text);
	if start > 0 then
	begin
		temp := Copy(Text, start + 9, 100);
		finish := Pos(WideString('"'), temp);
		get_build_FromText := Copy(temp, 0, finish - 1);
	end else begin
		get_build_FromText := '';
	end;
end;

function TCloudMailRu.get_upload_url_FromText(Text: WideString): WideString;
var
	start, start1, start2, finish, Length: Cardinal;
	temp: WideString;
begin
	start := Pos(WideString('mail.ru/upload/"'), Text);
	if start > 0 then
	begin
		start1 := start - 50;
		finish := start + 15;
		Length := finish - start1;
		temp := Copy(Text, start1, Length);
		start2 := Pos(WideString('https://'), temp);
		get_upload_url_FromText := Copy(temp, start2, StrLen(PWideChar(temp)) - start2);
	end else begin
		get_upload_url_FromText := '';
	end;
end;

function TCloudMailRu.get_x_page_id_FromText(Text: WideString): WideString;
var
	start: integer;
begin
	start := Pos(WideString('"x-page-id"'), Text);
	if start > 0 then
	begin
		get_x_page_id_FromText := Copy(Text, start + 13, 10);
	end else begin
		get_x_page_id_FromText := '';
	end;
end;

function TCloudMailRu.getShardFromJSON(JSON: WideString): WideString;
begin
	Result := ((((TJSONObject.ParseJSONValue(JSON) as TJSONObject).values['body'] as TJSONObject).values['get'] as TJSONArray).Items[0] as TJSONObject).values['url'].Value;
end;

function TCloudMailRu.getOAuthTokenInfoFromJson(JSON: WideString): TCloudMailRuOAuthInfo;
var
	Obj: TJSONObject;
begin
	try
		Obj := (TJSONObject.ParseJSONValue(JSON) as TJSONObject);
		with Result do
		begin
			if Assigned(Obj.values['error']) then error := Obj.values['error'].Value;
			if Assigned(Obj.values['error_code']) then error_code := Obj.values['error_code'].Value.ToInteger;
			if Assigned(Obj.values['error_description']) then error_description := Obj.values['error_description'].Value;
			if Assigned(Obj.values['expires_in']) then expires_in := Obj.values['expires_in'].Value.ToInteger;
			if Assigned(Obj.values['refresh_token']) then refresh_token := Obj.values['refresh_token'].Value;
			if Assigned(Obj.values['access_token']) then access_token := Obj.values['access_token'].Value;
		end;
	except
		on E: {EJSON}Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Can''t parse server answer: ' + JSON);
			Result.error_code := CLOUD_ERROR_UNKNOWN;
			Result.error := 'Answer parsing';
			Result.error_description := 'JSON parsing error: at ' + JSON;
		end;
	end;
end;

function TCloudMailRu.getUserSpaceFromJSON(JSON: WideString): TCloudMailRuSpaceInfo;
var
	Obj: TJSONObject;
begin
	Obj := (TJSONObject.ParseJSONValue(JSON) as TJSONObject).values['body'] as TJSONObject;
	with Result do
	begin
		if Assigned(Obj.values['overquota']) then overquota := Obj.values['overquota'].Value.ToBoolean;
		if Assigned(Obj.values['total']) then total := Obj.values['total'].Value.ToInt64;
		if Assigned(Obj.values['used']) then used := Obj.values['used'].Value.ToInt64;
	end;

end;

function TCloudMailRu.getDirListingFromJSON(JSON: WideString): TCloudMailRuDirListing;
var
	Obj: TJSONObject;
	J: integer;
	ResultItems: TCloudMailRuDirListing;
	A: TJSONArray;
begin
	A := ((TJSONObject.ParseJSONValue(JSON) as TJSONObject).values['body'] as TJSONObject).values['list'] as TJSONArray;
	SetLength(ResultItems, A.count);
	for J := 0 to A.count - 1 do
	begin
		Obj := A.Items[J] as TJSONObject;
		with ResultItems[J] do
		begin
			if Assigned(Obj.values['size']) then size := Obj.values['size'].Value.ToInt64;
			if Assigned(Obj.values['kind']) then kind := Obj.values['kind'].Value;
			if Assigned(Obj.values['weblink']) then weblink := Obj.values['weblink'].Value;
			if Assigned(Obj.values['type']) then type_ := Obj.values['type'].Value;
			if Assigned(Obj.values['home']) then home := Obj.values['home'].Value;
			if Assigned(Obj.values['name']) then name := Obj.values['name'].Value;
			if (type_ = TYPE_FILE) then
			begin
				if Assigned(Obj.values['mtime']) then mtime := Obj.values['mtime'].Value.ToInt64;
				if Assigned(Obj.values['virus_scan']) then virus_scan := Obj.values['virus_scan'].Value;
				if Assigned(Obj.values['hash']) then hash := Obj.values['hash'].Value;
			end else begin
				if Assigned(Obj.values['tree']) then tree := Obj.values['tree'].Value;
				if Assigned(Obj.values['grev']) then grev := Obj.values['grev'].Value.ToInteger;
				if Assigned(Obj.values['rev']) then rev := Obj.values['rev'].Value.ToInteger;
				if Assigned((Obj.values['count'] as TJSONObject).values['folders']) then folders_count := (Obj.values['count'] as TJSONObject).values['folders'].Value.ToInteger();
				if Assigned((Obj.values['count'] as TJSONObject).values['files']) then files_count := (Obj.values['count'] as TJSONObject).values['files'].Value.ToInteger();
				mtime := 0;
			end;
		end;
	end;

	Result := ResultItems;
end;

function TCloudMailRu.getFileStatusFromJSON(JSON: WideString): TCloudMailRuDirListingItem;
var
	Obj: TJSONObject;
begin
	Obj := (TJSONObject.ParseJSONValue(JSON) as TJSONObject).values['body'] as TJSONObject;
	with Result do
	begin
		if Assigned(Obj.values['size']) then size := Obj.values['size'].Value.ToInt64;
		if Assigned(Obj.values['kind']) then kind := Obj.values['kind'].Value;
		if Assigned(Obj.values['weblink']) then weblink := Obj.values['weblink'].Value;
		if Assigned(Obj.values['type']) then type_ := Obj.values['type'].Value;
		if Assigned(Obj.values['home']) then home := Obj.values['home'].Value;
		if Assigned(Obj.values['name']) then name := Obj.values['name'].Value;
		if (type_ = TYPE_FILE) then
		begin
			if Assigned(Obj.values['mtime']) then mtime := Obj.values['mtime'].Value.ToInteger;
			if Assigned(Obj.values['virus_scan']) then virus_scan := Obj.values['virus_scan'].Value;
			if Assigned(Obj.values['hash']) then hash := Obj.values['hash'].Value;
		end else begin
			if Assigned(Obj.values['tree']) then tree := Obj.values['tree'].Value;
			if Assigned(Obj.values['grev']) then grev := Obj.values['grev'].Value.ToInteger;
			if Assigned(Obj.values['rev']) then rev := Obj.values['rev'].Value.ToInteger;
			if Assigned((Obj.values['count'] as TJSONObject).values['folders']) then folders_count := (Obj.values['count'] as TJSONObject).values['folders'].Value.ToInteger();
			if Assigned((Obj.values['count'] as TJSONObject).values['files']) then files_count := (Obj.values['count'] as TJSONObject).values['files'].Value.ToInteger();
			mtime := 0;
		end;
	end;
end;

function TCloudMailRu.getOperationResultFromJSON(JSON: WideString; var OperationStatus: integer): integer;
var
	Obj: TJSONObject;
	error, nodename: WideString;
begin
	try
		Obj := TJSONObject.ParseJSONValue(JSON) as TJSONObject;

		OperationStatus := Obj.values['status'].Value.ToInteger;
		if OperationStatus <> 200 then
		begin
			if (Assigned((Obj.values['body'] as TJSONObject).values['home'])) then nodename := 'home'
			else if (Assigned((Obj.values['body'] as TJSONObject).values['weblink'])) then nodename := 'weblink'
			else
			begin
				Log(MSGTYPE_IMPORTANTERROR, 'Can''t parse server answer: ' + JSON);
				exit(CLOUD_ERROR_UNKNOWN);
			end;

			error := ((Obj.values['body'] as TJSONObject).values[nodename] as TJSONObject).values['error'].Value;
			if error = 'exists' then exit(CLOUD_ERROR_EXISTS);
			if error = 'required' then exit(CLOUD_ERROR_REQUIRED);
			if error = 'readonly' then exit(CLOUD_ERROR_READONLY);
			if error = 'read_only' then exit(CLOUD_ERROR_READONLY);
			if error = 'name_length_exceeded' then exit(CLOUD_ERROR_NAME_LENGTH_EXCEEDED);
			if error = 'unknown' then exit(CLOUD_ERROR_UNKNOWN);
			if error = 'overquota' then exit(CLOUD_ERROR_OVERQUOTA);
			if error = 'quota_exceeded' then exit(CLOUD_ERROR_OVERQUOTA);
			if error = 'invalid' then exit(CLOUD_ERROR_INVALID);
			if error = 'not_exists' then exit(CLOUD_ERROR_NOT_EXISTS);
			if error = 'own' then exit(CLOUD_ERROR_OWN);
			if error = 'name_too_long' then exit(CLOUD_ERROR_NAME_TOO_LONG);

			exit(CLOUD_ERROR_UNKNOWN); //Эту ошибку мы пока не встречали
		end;

	except
		on E: {EJSON}Exception do
		begin
			Log(MSGTYPE_IMPORTANTERROR, 'Can''t parse server answer: ' + JSON);
			exit(CLOUD_ERROR_UNKNOWN);
		end;
	end;
	Result := CLOUD_OPERATION_OK;
end;

function TCloudMailRu.getPublicLinkFromJSON(JSON: WideString): WideString;
begin
	Result := (TJSONObject.ParseJSONValue(JSON) as TJSONObject).values['body'].Value;
end;

end.
