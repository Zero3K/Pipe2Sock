#ifndef wshelper
#define wshelper


#ifdef __FB_WIN32__
  #undef integer
  #define integer long
  #include once "win/winsock2.bi"
#else  
  #include once "crt.bi"
  #include once "crt/sys/select.bi"
  #include once "crt/sys/socket.bi"
  #include once "crt/netinet/in.bi"
  #include once "crt/netdb.bi"
  #include once "crt/unistd.bi"
  #include once "crt/arpa/inet.bi"

  #define SOL_TCP         IPPROTO_TCP
  #ifndef FIONBIO
    #define FIONBIO &h5421 
  #endif
  #ifndef ioctl
    declare function ioctl cdecl alias "ioctl" (d as integer, request as integer, ...) as integer
  #endif

  #ifndef socket
    type socket as integer
  #endif
  #ifndef TCP_NODELAY
    const TCP_NODELAY = &h0001
  #endif
  #ifndef INVALID_SOCKET
    #define INVALID_SOCKET cuint(-1)
  #endif
  #ifndef timeval
    type timeval
      tv_sec as integer
      tv_usec as integer
    end type
  #endif
#endif

#ifndef true
#define true 1
#define false 0
#endif

const NOBLOCK = true
#define in4_addr ulong
#define ip4 as ulong

#ifdef __FB_WIN32__
  function hStart( byval verhigh as integer = 2, byval verlow as integer = 0 ) as integer
    dim wsaData as WSAData	
    if( WSAStartup( MAKEWORD( verhigh, verlow ), @wsaData ) <> 0 ) then
      return FALSE
    end if	
    if( wsaData.wVersion <> MAKEWORD( verhigh, verlow ) ) then
      WSACleanup( )	
      return FALSE
    end if	
    function = TRUE
  end function
  function hCleanup( ) as integer
    function = WSACleanup( )	
  end function  
#else
  function hStart( verhigh as integer = 2, verlow as integer = 0 ) as integer
    return true
  end function
  function hCleanup() as integer
    return true
  end function  
#endif

function hResolve cdecl ( byval hostname as zstring ptr) as long
	dim ac as zstring*80 = any, phost as zstring ptr = hostname
  if hostname = 0 then    
    if (gethostname(@ac, sizeof(ac)) = SOCKET_ERROR) then
    '  puts("failed...")
    'else
    '  printf(!"host = '%s'\n",ac)
    end if  
    hostname = @ac
  end if
  dim ia as in_addr
	dim hostentry as hostent ptr
	'' check if it's an ip address
	ia.S_addr = inet_addr( hostname )
	if ( ia.S_addr = INADDR_NONE ) then		
		'' if not, assume it's a name, resolve it
		hostentry = gethostbyname( hostname )
		if ( hostentry = 0 ) then
			exit function
		end if		
		dim as ulong uIp
    for N as integer = 0 to 99
      var pTemp = cptr( ulong ptr, (hostentry->h_addr_list)[N] )
      if pTemp = 0 then 
        if pHost=0 andalso N then 
          uIp = *cptr( ulong ptr, (hostentry->h_addr_list)[N-1] )
        end if
        exit for
      end if
      uIp = *pTemp : if phost=0 andalso (uIp and 255)=127 then continue for
      exit for
    next N
    return uIp
	else	
		'' just return the address
		function = ia.S_addr	
	end if	
end function

'':::::
sub hNonBlocking cdecl ( ss as SOCKET , NonBlocking as ulong = 0 )
  if NonBlocking then NonBlocking=1
  #ifdef __FB_WIN32__
    ioctlsocket( ss , FIONBIO , @NonBlocking )
  #else
    ioctl( ss , FIONBIO , @NonBlocking )
  #endif
end sub

'':::::
#define hOpenUDP() hOpen( IPPROTO_UDP )
function hOpen cdecl ( byval proto as long = IPPROTO_TCP, NonBlocking as ulong = 0 ) as SOCKET
	dim ts as SOCKET    
  dim as integer SockType = SOCK_STREAM
  if proto <> IPPROTO_TCP then SockType = SOCK_DGRAM  
  #ifdef __FB_WIN32__
    ts = WSASocket(AF_INET,SockType,proto,null,null,null)    
    'ts = OpenSocket(AF_INET,SockType,proto)
  #else
    ts = Socket_(AF_INET,SockType,proto)
  #endif
  if( ts = NULL ) then return NULL
  if NonBlocking then hNonBlocking( ts , 1 )      
  return ts
end function

'':::::
function hSockInfo cdecl (ss as SOCKET, byref LocalIP as long, byref LocalPort as long ) as integer
  dim sa as sockaddr_in = any
  var iAddrSz =  sizeof( sockaddr_in )
  function = (getsockname(ss, cptr( PSOCKADDR, @sa ), @iAddrSz)=0)
  LocalIP = sa.sin_addr.S_addr
  LocalPort = htons(sa.sin_port)
end function

'':::::
function hConnect cdecl overload (ss as SOCKET, ip as long, port as long ) as integer
	dim sa as sockaddr_in

	sa.sin_port			= htons( port )
	sa.sin_family		= AF_INET
	sa.sin_addr.S_addr	= ip
	
  var iNoDelay = true
  #ifndef DoNotDisableNagle
  setsockopt(ss,IPPROTO_TCP,TCP_NODELAY,cast(any ptr,@iNoDelay),sizeof(iNoDelay))
  #endif
  function = connect( ss, cptr( PSOCKADDR, @sa ), len( sa ) ) <> SOCKET_ERROR
  #ifndef DoNotDisableNagle
  setsockopt(ss,IPPROTO_TCP,TCP_NODELAY,cast(any ptr,@iNoDelay),sizeof(iNoDelay))
  #endif
	
end function
function hConnect cdecl overload (ss as SOCKET, ip as long, port as long, byref LocalIP as long,byref LocalPort as long) as integer
	dim sa as sockaddr_in = any

	sa.sin_port			= htons( port )
	sa.sin_family		= AF_INET
	sa.sin_addr.S_addr	= ip  
  
  var iNoDelay = true
  #ifndef DoNotDisableNagle
  setsockopt(ss,IPPROTO_TCP,TCP_NODELAY,cast(any ptr,@iNoDelay),sizeof(iNoDelay))
  #endif
	var iResu = connect( ss, cptr( PSOCKADDR, @sa ), sizeof( sockaddr_in ) ) <> SOCKET_ERROR
  #ifndef DoNotDisableNagle
  setsockopt(ss,IPPROTO_TCP,TCP_NODELAY,cast(any ptr,@iNoDelay),sizeof(iNoDelay))
  #endif
  
  if iResu then hSockInfo( ss , LocalIP , LocalPort )
  return iResu
 
end function

'':::::
#define hBindUDP hBind
function hBind cdecl ( byval ss as SOCKET, byval port as long, iIP as ulong = INADDR_ANY ) as integer
	dim sa as sockaddr_in

	sa.sin_port	   = htons( port )
	sa.sin_family	   = AF_INET
	sa.sin_addr.S_addr = iIP
	
	function = bind( ss, cptr( PSOCKADDR, @sa ), len( sa ) ) <> SOCKET_ERROR
	
end function

'':::::
function hListen cdecl ( byval ss as SOCKET, byval timeout as long = SOMAXCONN ) as integer
	
	function = listen( ss, timeout ) <> SOCKET_ERROR
	
end function

'':::::
function hAccept cdecl overload ( byval ss as SOCKET, byval sa as sockaddr_in ptr ) as SOCKET
	dim salen as integer 
	
	salen = len( sockaddr_in )
  var iNoDelay = true
  #ifndef DoNotDisableNagle
  setsockopt(ss,IPPROTO_TCP,TCP_NODELAY,cast(any ptr,@iNoDelay),sizeof(iNoDelay))
  #endif
	var iResu = accept( ss, cptr( PSOCKADDR, sa ), @salen )
  #ifndef DoNotDisableNagle
  setsockopt(iResu,IPPROTO_TCP,TCP_NODELAY,cast(any ptr,@iNoDelay),sizeof(iNoDelay))
  #endif
  return iResu

end function	
function hAccept cdecl ( byval ss as SOCKET, byref pIP as long, byref pPORT as long ) as SOCKET
  dim sa as sockaddr_in
	dim salen as integer = len( sockaddr_in )	
  var iNoDelay = true
  #ifndef DoNotDisableNagle
  setsockopt(ss,IPPROTO_TCP,TCP_NODELAY,cast(any ptr,@iNoDelay),sizeof(iNoDelay))
  #endif
  var iResu = accept( ss, cptr( PSOCKADDR, @sa ), @salen )  
  #ifndef DoNotDisableNagle
  setsockopt(iResu,IPPROTO_TCP,TCP_NODELAY,cast(any ptr,@iNoDelay),sizeof(iNoDelay))
  #endif
  if iResu = INVALID_SOCKET then
    pIP=0:pPort=0
  else
    'getpeername(ss,cptr( PSOCKADDR, @sa ), @salen)
    pIP = sa.sin_addr.S_addr
    pPORT = htons(sa.sin_port)  
  end if
  return iResu
end function
function hAccept cdecl ( byval ss as SOCKET ) as SOCKET  
  
  dim sa as sockaddr_in, salen as integer = sizeof( sockaddr_in )
  var iNoDelay = true
  #ifndef DoNotDisableNagle
  setsockopt(ss,IPPROTO_TCP,TCP_NODELAY,cast(any ptr,@iNoDelay),sizeof(iNoDelay))
  #endif
  var iResu = accept( ss, cptr( PSOCKADDR, @sa ), @salen )  
  #ifndef DoNotDisableNagle
  setsockopt(iResu,IPPROTO_TCP,TCP_NODELAY,cast(any ptr,@iNoDelay),sizeof(iNoDelay))
  #endif
  return iResu
  
end function	

'':::::
#define hCloseUDP hClose
function hClose cdecl ( byval ss as SOCKET ) as integer

	'shutdown( ss, 2 )	
  
	function = closesocket( ss )
	
end function

'':::::
function hSend cdecl ( byval ss as SOCKET, byval buffer as zstring ptr, byval bytes as long ) as integer

    function = send( ss, buffer, bytes, 0 )
    
end function

'':::::
function hSendUDP cdecl ( ss as SOCKET, IP as long, Port as long, buffer as zstring ptr, bytes as long ) as integer  
  
  dim sa as sockaddr_in
	sa.sin_port			= htons(port)
	sa.sin_family		= AF_INET
	sa.sin_addr.S_addr	= IP
  
  return SendTo(ss,buffer,bytes,null,cast(any ptr,@sa),len(sa))
end function

'':::::
function hReceive cdecl ( byval ss as SOCKET, byval buffer as zstring ptr, byval bytes as long ) as long

    function = recv( ss, buffer, bytes, 0 )
    
end function

'':::::
function hReceiveUDP cdecl ( ss as SOCKET,  byref pIP as long, byref pPORT as long , buffer as zstring ptr=0, bytes as long = -1 ) as long    
  dim sa as sockaddr_in
  dim as integer cliAddrLen=sizeof(sockaddr_in)
  if buffer=0 and bytes < 0 then 
    buffer=cast(any ptr,@buffer): bytes = 0
    function = RecvFrom(ss,buffer,bytes,MSG_PEEK,cast(any ptr,@sa),@cliAddrLen)
  else
    function = RecvFrom(ss,buffer,bytes,null,cast(any ptr,@sa),@cliAddrLen)
  end if
  pIP = sa.sin_addr.S_addr
  pPORT = htons(sa.sin_port)  
end function

'':::::
function hIPtoString cdecl ( byval ip as long ) as zstring ptr
	dim ia as in_addr	
	ia.S_addr = ip	
	var pzResu = inet_ntoa( ia )
  return iif(pzResu,pzResu,@"")
end function

'':::::

#if 0
  rem def __FB_WIN32__
  type fd_set2
    fd_count as uinteger
    fd_sock as socket
  end type
  #define hSelectUDP hSelect
  function hSelect cdecl( ss as SOCKET, CheckForWrite as long = 0, iTimeoutMS as long = 0) as integer
    dim as timeval tTimeOut = any
    if iTimeoutMS then 
      tTimeout = type(iTimeoutMS\1000,(iTimeOutMS mod 1000)*1000)  
    else
      tTimeout = type(0,0)
    end if
    if CheckForWrite then
      dim as fd_set2 WriteSock = type(1,ss)    
      return select_(null,null,cast(any ptr,@WriteSock),null,@tTimeout)
    else
      dim as fd_set2 ReadSock = type(1,ss)
      return select_(null,cast(any ptr,@ReadSock),null,null,@tTimeout)
    end if
  end function
  #define hSelectErrorUDP hSelectError
  function hSelectError cdecl ( ss as SOCKET ) as integer
    dim as timeval tTimeOut = type(0,0)    
    dim as fd_set2 ErrorSock = type(1,ss)
    return select_(null,null,null,cast(any ptr,@ErrorSock),@tTimeout)  
  end function
  #undef fd_set2
#else
  #define hSelectUDP hSelect
  function hSelect cdecl ( s as SOCKET, CheckForWrite as long = 0, iTimeoutMS as long = 0) as integer  
    dim as timeval tTimeOut = any
    if iTimeoutMS then 
      tTimeout = type(iTimeoutMS\1000,(iTimeOutMS mod 1000)*1000)  
    else
      tTimeout = type(0,0)
    end if
    dim as fd_set tSock
    FD_SET_(s,@tSock)
    if CheckForWrite then
      return select_(s+1,null,@tSock,null,@tTimeout)
    else	
      return select_(s+1,@tSock,null,null,@tTimeout)
    end if
  end function
  function hSelectError cdecl ( s as SOCKET , iTimeoutMS as long = 0 ) as integer  
    dim as timeval tTimeOut = any
    if iTimeoutMS then 
      tTimeout = type(iTimeoutMS\1000,(iTimeOutMS mod 1000)*1000)  
    else
      tTimeout = type(0,0)
    end if
    dim as fd_set tSock
    FD_SET_(s,@tSock)
    return select_(s+1,null,null,@tSock,@tTimeout)
  end function
  
#endif

#ifdef hHelperApi
  'http://api.ipify.org?format=json
  '{"ip":"189.49.141.147"}
  #if 1
    function hGetExternalIP cdecl ( lBindIp as LONG = 0 ) as string
      var sIP = "", Sock = hOpen()
      while Sock
        if lBindIp then hBind( Sock , lBindIp )
        var IP = hResolve("api.ipify.org")
        if IP = 0 then exit while
        if hConnect(Sock,IP,80)=0 then exit while
        var sHeader = _
        "GET /?format=json HTTP/1.1" !"\r\n" _
        "Host: api.ipify.org"        !"\r\n" _
        "Accept: text/plain"         !"\r\n" _
        "Connection: close"          !"\r\n\r\n"
        if hSend(Sock,sHeader,len(sHeader))=0 then exit while
        var sBuff = space(1024),iPos=0,iResu=0,iDone=0
        var iPosIP=0,iDots=0,iDigs=0,iBlanks=0,iChar=0
        dim as zstring*16 zIP
        do
          if hSelect(Sock) then
            iResu = hReceive(Sock,strptr(sBuff)+iPos,1024-iPos)        
            if iResu <= 0 then exit while
            iPos += iResu:iResu = instr(1,sBuff,"{""ip"":""")+6
            while iResu > 7
              iChar = sBuff[iResu]
              'print chr(iChar);" ["+zIP+"]",iDots;iDigs;iBlanks
              select case iChar
              case 32 'spaces
                if iDots = 3 andalso iDigs then iDone=1:exit while
                iBlanks += 1: if iBlanks > 3 then exit while
              case asc("0") to asc("9")
                if iDigs=2 andalso zIP[iPosIP-2] > asc("2") then exit while
                iDigs += 1: iBlanks=0
                if iDigs > 3 then exit while
                zIP[iPosIP] = iChar: iPosIP += 1
              case asc(".")
                if iDigs = 0 then exit while
                iDots += 1: iDigs=0:iBlanks=0
                if iDots > 3 then exit while
                zIP[iPosIP] = iChar: iPosIP += 1
              case else
                if iDots = 3 andalso iDigs then iDone=1
                exit while
              end select
              iResu += 1
            wend
            if iDone then sIP = zIP:exit while
          else
            sleep 1,1
          end if
        loop
      wend
      hClose(Sock):Sock=0
      return sIP
    end function
  #else
    function hGetExternalIP cdecl () as string
      var sIP = "", Sock = hOpen()
      while Sock
        var IP = hResolve("checkip.dyndns.org")
        if IP = 0 then exit while
        if hConnect(Sock,IP,80)=0 then exit while
        var sHeader = _
        "GET /mobile/ HTTP/1.1"    !"\r\n" _
        "Host: checkip.dyndns.org" !"\r\n" _
        "Accept: text/plain"       !"\r\n" _
        "Connection: close"        !"\r\n\r\n"
        if hSend(Sock,sHeader,len(sHeader))=0 then exit while
        var sBuff = space(1024),iPos=0,iResu=0,iDone=0
        var iPosIP=0,iDots=0,iDigs=0,iBlanks=0,iChar=0
        dim as zstring*16 zIP
        do
          if hSelect(Sock) then
            iResu = hReceive(Sock,strptr(sBuff)+iPos,1024-iPos)        
            if iResu <= 0 then exit while
            iPos += iResu:iResu = instr(1,sBuff,"ddress:")+6
            while iResu > 7
              iChar = sBuff[iResu]
              'print chr(iChar);" ["+zIP+"]",iDots;iDigs;iBlanks
              select case iChar
              case 32 'spaces
                if iDots = 3 andalso iDigs then iDone=1:exit while
                iBlanks += 1: if iBlanks > 3 then exit while
              case asc("0") to asc("9")
                if iDigs=2 andalso zIP[iPosIP-2] > asc("2") then exit while
                iDigs += 1: iBlanks=0
                if iDigs > 3 then exit while
                zIP[iPosIP] = iChar: iPosIP += 1
              case asc(".")
                if iDigs = 0 then exit while
                iDots += 1: iDigs=0:iBlanks=0
                if iDots > 3 then exit while
                zIP[iPosIP] = iChar: iPosIP += 1
              case else
                if iDots = 3 andalso iDigs then iDone=1
                exit while
              end select
              iResu += 1
            wend
            if iDone then sIP = zIP:exit while
          else
            sleep 1,1
          end if
        loop
      wend
      hClose(Sock):Sock=0
      return sIP
    end function
  #endif
  #endif
  
  'end extern
  
  hStart()
#endif