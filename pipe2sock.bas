#define fbc -s gui

#include "crt.bi"
#include "windows.bi"
#include "wshelper.bas"

const sAppTitle = "Pipe2Sock v1.0 by Mysoft (31/jan/2020)" 

#define Fatal() if iUseConsole then puts("Any Key to Quit."):sleep:system 1 else system 1
#macro printf2( _f , _p... )
  if iUseConsole then 
    printf( _f , _p )
  else
    dim as zstring*4096 zBuff = any
    sprintf( zBuff , _f , _p )
    MessageBox(0,zBuff,sAppTitle,MB_ICONINFORMATION or MB_SETFOREGROUND or MB_TOPMOST)
  end if
#endmacro
#macro puts2( _p )
  if iUseConsole then 
    puts( _p )
  else    
    MessageBox(0,_p,sAppTitle,MB_ICONINFORMATION or MB_SETFOREGROUND or MB_TOPMOST)
  end if
#endmacro

static shared as integer iVerbose = 0, iUseConsole = 1, iAutoQuit = 0
static shared as string sPipeName, sSockHost
static shared as long iSockPort = 0
Const BufferSz = 65536

function WsaErrorName( iCode as uinteger , pzErrorDesc as zstring ptr ptr = 0 ) as zstring ptr
  if pzErrorDesc = 0 then pzErrorDesc = cast(any ptr,@pzErrorDesc)
  select case iCode
  
  case 0               : *pzErrorDesc = @"The Operation Suceeded."                                            : return @"WSAE_SUCCESS"
  'FD_CONNECT
  case WSAEADDRINUSE   : *pzErrorDesc = @"The specified address is already in use."                           : return @"WSAEADDRINUSE"
  case WSAEADDRNOTAVAIL: *pzErrorDesc = @"The specified address is not available from the local machine."     : return @"WSAEADDRNOTAVAIL"
  case WSAEAFNOSUPPORT : *pzErrorDesc = @"Addresses in the specified family cannot be used with this socket." : return @"WSAEAFNOSUPPORT"
  case WSAECONNREFUSED : *pzErrorDesc = @"The attempt to connect was forcefully rejected."                    : return @"WSAECONNREFUSED"
  case WSAENETUNREACH  : *pzErrorDesc = @"The network cannot be reached from this host at this time."         : return @"WSAENETUNREACH"
  case WSAENOBUFS      : *pzErrorDesc = @"No buffer space is available. The socket cannot be connected."      : return @"WSAENOBUFS"
  case WSAETIMEDOUT    : *pzErrorDesc = @"Attempt to connect timed out without establishing a connection"     : return @"WSAETIMEDOUT"
  'FD_CLOSE
  case WSAENETDOWN	   : *pzErrorDesc = @"The network subsystem has failed."                                  : return @"WSAENETDOWN"
  case WSAECONNRESET   : *pzErrorDesc = @"The connection was reset by the remote side."                       : return @"WSAECONNRESET"
  case WSAECONNABORTED : *pzErrorDesc = @"The connection was terminated due to a time-out or other failure."  : return @"WSAECONNABORTED"
  case else
    static as zstring*16 zNum = any
    sprintf(zNum,"#%08X",iCode)
    *pzErrorDesc = @"Unknown error code.."
    return @zNum
  end select
end function

sub ConnectionThread( pCtx as any ptr )
  
  'const sPipeName = "\\.\pipe\ros" 
  'const sSockHost = "localhost"
  'const iSockPort = 1001

  'Create a pipe to read from process
  const _PipeMode_ = PIPE_ACCESS_DUPLEX or FILE_FLAG_OVERLAPPED
  const _PipeType_ = PIPE_TYPE_BYTE or PIPE_WAIT
  
  if iUseConsole andalso iVerbose then 
    printf(!"Creating named pipe '%s'\n",sPipeName)
  end if
  var hPipe = CreateNamedPipe(sPipeName,_PipeMode_,_PipeType_,1,BufferSz,BufferSz,0,0)
  if hPipe = INVALID_HANDLE_VALUE then
    printf2(!"Failed to create named pipe '%s'\n", sPipeName)
    Fatal()
  end if  
  
  dim as long iIp
  if len(sSockHost) then
    iIP = hResolve( sSockHost )
    if iUseConsole andalso iVerbose then 
      printf(!"'%s' resolved to %s\n",sSockHost,hIptoString(iIP))
    end if
    if iIP = 0 then 
      printf2("Failed to resolve '%s'\n", sSockHost)
      CloseHandle(hPipe)
      Fatal()
    end if
  end if
  
  dim as zstring*BufferSz zBuf = any
  dim as integer iBytesRead , iPipeReady=0 , iSockReady=0  
  dim as SOCKET hSock, hServerSock = hOpen()
  
  if iUseConsole andalso iVerbose then 
    printf(!"Creating sock server on %s:%i\n",hIpToString(iIP),iSockPort)
  end if
  if hBind( hServerSock , iSockPort , iIP )=0 orelse hListen( hServerSock )=0 then
    printf2(!"Failed to listen on %s:%i\n",hIpToString(iIP),iSockPort)    
    CloseHandle(hPipe)
    Fatal()
  end if
  
  dim as HANDLE hPipeEv = CreateEvent(NULL,TRUE,FALSE,NULL)  
  dim as WSAEVENT hSockEv = WSACreateEvent(), hServerSockEv = WSACreateEvent()
  dim as OVERLAPPED tOvr : tOvr.hEvent = hPipeEv
  WSAEventSelect( hServerSock , hServerSockEv , FD_ACCEPT )
  ConnectNamedPipe( hPipe , @tOvr )
  if iUseConsole orelse iVerbose then 
    printf2(!"Pipe '%s' is waiting...\n",sPipeName)
  end if
  if iSockPort = 0 then hSockInfo( hServerSock , 0 , iSockPort )
  if iUseConsole orelse iVerbose then 
    printf2(!"Socket listening on %s:%i\n",hIPtoString(iIp),iSockPort)
  end if
  dim as HANDLE aSock(2) = { hPipeEv , hServerSockEv , hSockEv  }
  
  if iVerbose then 
    puts2("Main socket/pipe transaction loop")
  end if  
  
  do    
    select case WaitForMultipleObjects( 2+iif(hSock,1,0) , @aSock(0) , false , INFINITE )
    case WAIT_OBJECT_0+0 'event from the pipe
      ResetEvent( hPipeEV )
      if iPipeReady then              
        'puts2("Someone sent data from the pipe")
        if GetOverlappedResult( hPipe , @tOvr , @iBytesRead , false )=0 then          
          var iErr = GetLastError()
          if iErr <> ERROR_BROKEN_PIPE then            
            if iUseCOnsole orelse iVerbose then
              printf2(!"Failed to read from pipe? Err=%08X\n",iErr)
            end if
            FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )            
            ConnectNamedPipe( hPipe , @tOvr ) : iPipeReady = 0
            if iUseConsole then 
              printf(!"Pipe '%s' is waiting...\n",sPipeName)
            end if
            if iAutoQuit then exit sub
            continue do
          end if          
        else '536
          if iUseConsole andalso iVerbose then 
            printf2(!"Read %i bytes from pipe\n",iBytesRead)          
          end if
          if iSockReady = 0 then
            if iUseConsole andalso iVerbose then 
              puts("Bytes received but no socket connected... discarding")
            end if
          else
            do            
              var iResu = hSend( hSock , zBuf , iBytesRead )                                    
              if iResu = iBytesRead then exit do
              select case WSAGetLastError()
              case WSAEWOULDBLOCK
                if iResu > 0 then 
                  printf2(!"Partial write??? {%i~%i}\n",iResu,iBytesRead)
                  if iAutoQuit then exit sub
                  sleep
                end if
                sleep 1,1: continue do
              case else
                if iUseConsole orelse iVerbose then
                  printf2(!"Failed to send data to socket: %08X\n",WSAGetLastError())                
                  puts2("Disconnecting socket.")
                end if
                hClose(hSock):hSock=0:iSockReady=0
                if iAutoQuit then exit sub
                iSockReady=0:continue do,do
              end select
            loop
            if iUseConsole andalso iVerbose then 
              printf(!"Written %i bytes to socket\n",iBytesRead)
            end if
          end if          
        end if  
        
        var iResu = ReadFile( hPipe , @zBuf , sizeof(zBuf) , 0 , @tOvr )
        if iResu = 0 then
          var iErr = GetLastError()
          select case iErr
          case ERROR_IO_PENDING 'its all right :)
          case ERROR_MORE_DATA
            puts2("ERROR_MORE_DATA") 
          case ERROR_HANDLE_EOF
            puts2("ERROR_HANDLE_EOF")
          case ERROR_BROKEN_PIPE 'finished
            if iUseConsole then 
              puts("Broken pipe (finished?)")
            end if
            FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )            
            ConnectNamedPipe( hPipe , @tOvr ) : iPipeReady = 0
            if iAutoQuit then exit sub 
            if iUseConsole then 
              printf(!"Pipe '%s' is waiting...\n",sPipeName)
            end if
          case else
            if iUseConsole orelse iVerbose then
              printf2("Unknown error reading from pipe: %i",iErr)
            end if
            FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )            
            ConnectNamedPipe( hPipe , @tOvr ) : iPipeReady = 0                
            if iUseConsole then 
              printf(!"Pipe '%s' is waiting...\n",sPipeName)                
            end if
            if iAutoQuit then exit sub
          end select
        end if        
      else
        if iUseConsole then 
          puts2("Someone connected to the pipe")      
        end if
        var iResu = ReadFile( hPipe , @zBuf , sizeof(zBuf) , 0 , @tOvr )
        if iResu = 0 then
          var iErr = GetLastError()
          select case iErr
          case ERROR_IO_PENDING 'its all right :)
          case ERROR_MORE_DATA
            puts2("ERROR_MORE_DATA") 
          case ERROR_HANDLE_EOF
            puts2("ERROR_HANDLE_EOF")
          case ERROR_BROKEN_PIPE 'finished
            if iUseConsole orelse iVerbose then
              puts2("Broken pipe (finished?)")
            end if
            FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )
            ConnectNamedPipe( hPipe , @tOvr ) : iPipeReady = 0
            if iUseConsole then 
              printf(!"Pipe '%s' is waiting...\n",sPipeName)
            end if
          case else              
            if iUseConsole orelse iVerbose then
              printf2("Unknown error reading from pipe: %i",iErr)
            end if
            FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )            
            ConnectNamedPipe( hPipe , @tOvr ) : iPipeReady = 0            
            if iUseConsole then 
              printf2(!"Pipe '%s' is waiting...\n",sPipeName)
            end if
            if iAutoQuit then exit sub
          end select
        else
          iPipeReady = 1
        end if        
      end if
     
    case WAIT_OBJECT_0+1 'event from server socket
      dim as WSANETWORKEVENTS tEvs
      dim as long iRemIP,iRemPort      
      if WSAEnumNetworkEvents( hServerSock , hServerSockEv , @tEvs ) then        
        puts2("WSAEnumNetworkEvents() failed")
        if iAutoQuit then exit sub
        WSAResetEvent( hSockEv ) : continue do
      else
        if (tEvs.lNetworkEvents and FD_ACCEPT) then
          var hTemp = hAccept(hServerSock,iRemIP,iRemPort)
          if iSockReady then 
            if hSock then hClose(hSock):hSock=0
            if iUseConsole orelse iVerbose then
              printf2( !"Already connected... ignoring connection from %s:%i\n",hIpToString(iRemIp),iRemPort )
            end if
          else          
            hSock = hTemp : iSockReady = 1
            WSAEventSelect( hSock , hSockEv , FD_READ or FD_WRITE or FD_CLOSE )            
            if iUseCOnsole orelse iVerbose then
              printf2( !"%s:%i connected!\n",hIpToString(iRemIp),iRemPort )
            end if
          end if
        end if
      end if
    case WAIT_OBJECT_0+2 'event from the socket
      'puts2("Socket Event")
      dim as WSANETWORKEVENTS tEvs
      dim as zstring ptr pzDesc = @"Wut?"
      if hSock = 0 then WSAResetEvent( hSockEv ):continue do
      if WSAEnumNetworkEvents( hSock , hSockEv , @tEvs ) then        
        puts2("WSAEnumNetworkEvents() failed")
        WSAResetEvent( hSockEv ) : continue do
      end if
      if (tEvs.lNetworkEvents and FD_READ) then
        if iUseConsole andalso iVerbose then 
          printf2(!"FD_READ: %s (%s)\n",pzDesc,WsaErrorName(tEvs.iErrorCode(FD_READ_BIT),@pzDesc))
        end if
      end if
      #if 0
        if (tEvs.lNetworkEvents and FD_WRITE) then
          if tEvs.iErrorCode(FD_WRITE_BIT) then          
            printf2(!"FD_WRITE: %s (%s)\n",pzDesc,WsaErrorName(tEvs.iErrorCode(FD_WRITE_BIT),@pzDesc))
            if iState <> csWaitPipe then
              'when it errors we flush and disconnect the client
              FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )
              'and get ready for another client
              ConnectNamedPipe( hPipe , @tOvr ) : iState = csWaitPipe
              printf2(!"Pipe '%s' is waiting...\n",sPipeName)
            end if
          else
            'schedule for reading on PIPE
            var iResu = ReadFile( hPipe , @zBuf , sizeof(zBuf) , 0 , @tOvr )
            if iResu = 0 then
              var iErr = GetLastError()
              select case iErr
              case ERROR_IO_PENDING 'its all right :)
              case ERROR_MORE_DATA
                puts2("ERROR_MORE_DATA") 
              case ERROR_HANDLE_EOF
                puts2("ERROR_HANDLE_EOF")
              case ERROR_BROKEN_PIPE 'finished
                puts2("Broken pipe (finished?)")
                FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )            
                ConnectNamedPipe( hPipe , @tOvr ) 
                puts2("Closing Socket")
                hClose( hSock ):hSock=0: iState = csWaitPipe
                printf2(!"Pipe '%s' is waiting...\n",sPipeName)
              case else
                printf2("Unknown error reading from pipe: %i",iErr)
                FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )            
                ConnectNamedPipe( hPipe , @tOvr ) 
                hClose( hSock ):hSock=0: iState = csWaitPipe
                printf2(!"Pipe '%s' is waiting...\n",sPipeName)              
              end select
            end if
          end if
        end if      
        if (tEvs.lNetworkEvents and FD_CONNECT) then
          printf2(!"FD_CONNECT: %s (%s)\n",pzDesc,WsaErrorName(tEvs.iErrorCode(FD_CONNECT_BIT),@pzDesc))
          if tEvs.iErrorCode(FD_CONNECT_BIT) then
            if iState <> csWaitPipe then
              'printf2(!"FD_CONNECT: %s (%s)\n",pzDesc,WsaErrorName(tEvs.iErrorCode(FD_CONNECT_BIT),@pzDesc))
              'when it errors we flush and disconnect the client
              FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )
              'and get ready for another client
              ConnectNamedPipe( hPipe , @tOvr ) : iState = csWaitPipe
              printf2(!"Pipe '%s' is waiting...\n",sPipeName)
            end if
          else
            puts2("Socket connected.") : iState = csReady
            var iResu = ReadFile( hPipe , @zBuf , sizeof(zBuf) , 0 , @tOvr )
            if iResu = 0 then
              var iErr = GetLastError()
              select case iErr
              case ERROR_IO_PENDING 'its all right :)
              case ERROR_MORE_DATA
                puts2("ERROR_MORE_DATA") 
              case ERROR_HANDLE_EOF
                puts2("ERROR_HANDLE_EOF")
              case ERROR_BROKEN_PIPE 'finished
                puts2("Broken pipe (finished?)")
                FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )            
                ConnectNamedPipe( hPipe , @tOvr ) 
                puts2("Closing Socket.")
                hClose( hSock ) : iState = csWaitPipe
                printf2(!"Pipe '%s' is waiting...\n",sPipeName)
              case else              
                printf2("Unknown error reading from pipe: %i",iErr)
                FlushFileBuffers( hPipe ): DisconnectNamedPipe( hPipe )            
                ConnectNamedPipe( hPipe , @tOvr ) 
                hClose( hSock ) : iState = csWaitPipe
                printf2(!"Pipe '%s' is waiting...\n",sPipeName)              
              end select
            end if
          end if
        end if
      #endif
      if (tEvs.lNetworkEvents and FD_CLOSE) then
        'if tEvs.iErrorCode(FD_CLOSE_BIT) then
        if iUseConsole orelse iVerbose then
          printf2(!"FD_CLOSE: %s (%s)\n",pzDesc,WsaErrorName(tEvs.iErrorCode(FD_CLOSE_BIT),@pzDesc))
        end if
        'end if
        'and get ready for another client
        hClose( hSock ) : hSock = 0 : iSockReady = 0
        if iAutoQuit then exit sub
      end if
    case else
      if iAutoQuit then exit sub
      puts2("Event error...") : exit do
    end select
  loop

end sub

scope 'main
  hStart()
  
  var iN = 1, iOptReady = 0
  sSockHost = ""
  
  'Check for the special -n option that must be checked before any other options are processed
  do
    var sN = command(iN) : iN += 1  
    if len(sN)=0 then exit do    
    sN = lcase(trim(sN))
    if sN[0] = asc("/") then sN[0] = asc("-")
    if sN = "-n" then iUseConsole = 0 : exit do
  loop
  iN = 1
  
  'if want a console then create one
  if iUseConsole then
    AllocConsole()
    freopen("CON", "r", stdin)
    freopen("CON", "w", stdout)
    freopen("CON", "w", stderr)
  end if
  
  'process command line parameters
  do
    var sN = command(iN) : iN += 1  
    if len(sN)=0 then 
      if iOptReady then exit do else sN = "-h"
    end if
    
    sN = trim(sN)
    if sN[0] = asc("/") then sN[0] = asc("-")
    if sN[0] <> asc("-") then 
      if iOptReady then
        sN = "-h"
      else
        'bare check for pipe name validity
        sPipeName = sN : sN = "-h"
        if len(sPipeName) then 
          if lcase(left(sPipeName,9)) <> "\\.\pipe\" then
            puts2("pipe name must be '\\.\pipe\name'")
            Fatal()
          end if
          iOptReady = 1: continue do
        end if
      end if
    end if
    
    var sNL = lcase(sN)
        
    select case sNL  
    case "-p"
      iSockPort = valint(trim(command(iN))): iN += 1
      if iSockPort < 1 or iSockPort > 65535 then
        puts2("Invalid Port Number")      
        Fatal()
      end if
    case "-a"
      sSockHost = trim(command(iN)): iN += 1
      if len(sSockHost)=0 then 
        puts2("Invalid hostname")      
        Fatal()
      end if
    case "-v"
      iVerbose = 1
    case "-q"
      iAutoQuit = 1
    case "-n"
      'Already processed :)
    case "-h"
      printf2( _
      !"%s\r\nUsage:\r\n" _
      !"Pipe2Sock [options] pipename\r\n\r\n" _
      !"Options:\r\n" _
      !"  -h       show this help\r\n" _
      !"  -p #     bind socket to port #\r\n" _
      !"  -a host  bind socket to host/ip\r\n" _
      !"  -q       quit when an error happens.\r\n" _
      !"  -n       dont create a console\r\n" _
      !"  -v       be verbose\r\n",iif(iUseConsole,@sAppTitle,@""))
      if iUseConsole then puts(!"\nAny Key to exit"):sleep
      system 0
    case else
      printf2(!"unknown option '%s'\n",sN)
      Fatal()
    end select
  loop
  
  'execute connection process (multiple pipes/sockets wanted?)
  ConnectionThread( null )
  if iUseConsole then 
    puts(!"\nAny Key to exit")
    sleep
  else
    puts2("Program is closing now...")
  end if
end scope
