/// SRCI bridge: TCP/IP server for a Python client, telegrams to/from the robot over PROFINET
FUNCTION_BLOCK FB_SrciTcpIpBridge
// -------------------------------------------------------------------------
//  SRCI Robot Library
// -------------------------------------------------------------------------
//
//  Object:      FB_SrciTcpIpBridge (CODESYS)
//  Author:      Thorsten Brach
//  Date:        2026-10-04
//
//  Description:
//    The PLC as TCP/IP bridge between the SRCI client in Python (SRCI_PY,
//    TcpTransport) and a robot controller on PROFINET. Same interface and
//    protocol as the TwinCAT version (SRCI_PY docs/TRANSPORT.md):
//      - the PLC is the TCP server, Python the TCP client (one client at a time,
//        a new client replaces the old one);
//      - raw SRCI telegrams without framing, fixed lengths;
//      - lockstep: Python sends one telegram PLC -> RC (LengthPlcToRob bytes), the
//        bridge copies it into the PROFINET outputs (RobotOutData) and answers with
//        exactly one telegram RC -> PLC (LengthRobToPlc bytes) from the PROFINET
//        inputs (RobotInData). The bridge never sends on its own.
//    Python is the cycle master; the SRCI logic (MC_RobotTaskFB, commands) runs in
//    Python, the PLC only forwards the bytes.
//    When the client disconnects, the last telegram stays in the outputs: its
//    LifeSign does not change any more and the RC leaves the initialized state
//    (LifeSign timeout), as with a stopped PLC.
//
//    AnswerDelayCycles = 0: the answer is sent in the PLC cycle in which the request
//    was complete (inputs of this cycle). 1..n: the answer is sent n cycles later,
//    i.e. after the outputs went out over PROFINET (newer inputs, longer round trip).
//
//    Needs the library SysSocket (CODESYS). All sockets are non-blocking, so every
//    call returns at once; a request and its answer are usually handled in the
//    same PLC cycle.
//
//  Copyright:
//    (C) 2026 Thorsten Brach. All rights reserved
//             Licensed under the MIT License.
//
//  Disclaimer:
//    This project is provided without any guarantee and can be used for
//    private and commercial purposes. Any use is at the user's
//    own risk and responsibility.
//
// -------------------------------------------------------------------------
VAR_INPUT
  /// Open the server and forward telegrams (FALSE: close client and server)
  Enable            : BOOL;
  /// Local IP address to listen on ('' = all network adapters)
  LocalHost         : STRING(15) := '';
  /// TCP port of the server
  LocalPort         : UINT := 5000;
  /// Telegram length PLC -> RC [bytes] (request of Python, TelegramLengthPlcToRob)
  LengthPlcToRob    : UDINT := 256;
  /// Telegram length RC -> PLC [bytes] (answer to Python, TelegramLengthRobToPlc)
  LengthRobToPlc    : UDINT := 256;
  /// PLC cycles between a complete request and the answer (0 = same cycle)
  AnswerDelayCycles : UDINT := 0;
  /// Wait time before a new attempt after an error of the server (create/bind/listen/accept)
  RetryDelay        : TIME := T#2S;
END_VAR
VAR_IN_OUT
  /// PROFINET outputs of the robot: telegram PLC -> RC
  RobotOutData      : ARRAY[*] OF BYTE;
  /// PROFINET inputs of the robot: telegram RC -> PLC
  RobotInData       : ARRAY[*] OF BYTE;
END_VAR
VAR_OUTPUT
  /// Server is listening for a client
  Listening         : BOOL;
  /// A client is connected
  Connected         : BOOL;
  /// A request was copied into RobotOutData in this call
  NewTelegram       : BOOL;
  /// Error of the last connection / server attempt (reset with the next successful connection)
  Error             : BOOL;
  /// Error ID: runtime error code of SysSocket (CmpErrors, e.g. 16#207 address in use),
  /// 16#FFFD RobotOutData/RobotInData smaller than LengthPlcToRob/LengthRobToPlc or larger than
  /// the internal buffers, 16#FFFE invalid step
  ErrorID           : UDINT;
  /// Step in which the error occurred
  ErrorStep         : DINT;
  /// Number of forwarded telegrams since the start
  Telegrams         : UDINT;
  /// Number of accepted clients since the start
  Connections       : UDINT;
  /// Time between the last two requests (cycle time of the Python client)
  Interval          : TIME;
  /// Longest time between two requests of the current client (check against the LifeSign timeout)
  MaxInterval       : TIME;
END_VAR
VAR
  /// Step of the state machine
  _step             : DINT;
  /// Handle of the listener
  _listener         : RTS_IEC_HANDLE := RTS_INVALID_HANDLE;
  /// Handle of the connected client
  _socket           : RTS_IEC_HANDLE := RTS_INVALID_HANDLE;
  /// Handle of a new client (accepted while waiting or replacing the connected one)
  _newSocket        : RTS_IEC_HANDLE := RTS_INVALID_HANDLE;
  /// Result of the last socket call
  _result           : RTS_IEC_RESULT;
  /// Local address of the server
  _address          : SOCKADDRESS;
  /// Address of the accepted client
  _clientAddress    : SOCKADDRESS;
  /// Size of the client address
  _addressSize      : DINT;
  /// Copy of LocalHost for SysSockInetAddr (REFERENCE TO STRING)
  _host             : STRING;
  /// Value of a socket option / io-control
  _value            : DINT;
  /// Number of bytes for a receive / send call
  _length           : DINT;
  /// Bytes received / sent by the last call
  _count            : __XINT;
  /// Receive buffer of the request (it can arrive in several parts)
  _rxBuffer         : ARRAY[0..1023] OF BYTE;
  /// Bytes of the current request received so far
  _rxCount          : UDINT;
  /// Answer (copy of RobotInData when it is sent)
  _txBuffer         : ARRAY[0..1023] OF BYTE;
  /// Bytes of the answer sent so far
  _txCount          : UDINT;
  /// PLC cycles waited for the answer
  _delayCount       : UDINT;
  /// Time stamp of the last complete request
  _lastRequest      : TIME;
  /// The client is closed because the server is disabled
  _shutdown         : BOOL;
  /// Wait time after an error of the server
  _timer            : TON;
  /// Loop counter: several steps can be done in one call
  _loop             : DINT;
  /// Index for copying the telegrams
  _idx              : UDINT;
END_VAR
VAR CONSTANT
  /// Result code: no error (CmpErrors ERR_OK)
  RESULT_OK         : RTS_IEC_RESULT := 16#0;
  /// Result code: the socket is non-blocking and the call would block (CmpErrors ERR_SOCK_WOULDBLOCK)
  RESULT_WOULDBLOCK : RTS_IEC_RESULT := 16#206;
END_VAR

  NewTelegram := FALSE;

  // disabled -> close the client (if connected), then the listener
  IF ( NOT Enable )
  THEN
    IF (( _step >= 25 ) AND
        ( _step <  70 ))
    THEN
      _shutdown := TRUE;
      _step     := 70;
    ELSIF ( _step = 20 )
    THEN
      _step := 80;
    END_IF
  END_IF

  // several steps in one call (e.g. request complete -> send the answer at once)
  FOR _loop := 1 TO 4
  DO
    CASE _step OF

      0: // idle - start the server ?
         // the telegram buffers must hold the telegram lengths
         IF (( DINT_TO_UDINT(UPPER_BOUND(RobotOutData, 1) - LOWER_BOUND(RobotOutData, 1) + 1) < LengthPlcToRob ) OR
             ( DINT_TO_UDINT(UPPER_BOUND(RobotInData,  1) - LOWER_BOUND(RobotInData,  1) + 1) < LengthRobToPlc ) OR
             ( LengthPlcToRob > SIZEOF(_rxBuffer)                                                            ) OR
             ( LengthRobToPlc > SIZEOF(_txBuffer)                                                            ) OR
             ( LengthPlcToRob = 0                                                                            ) OR
             ( LengthRobToPlc = 0                                                                            ))
         THEN
           ErrorID   := 16#FFFD;
           ErrorStep := _step;
           Error     := TRUE;
           EXIT;
         END_IF
         IF ( NOT Enable )
         THEN
           EXIT;
         END_IF
         _step := 10;

      10: // open the server port: create, reuse the address, non-blocking, bind, listen
          _listener := SysSockCreate( iAddressFamily := SOCKET_AF_INET,
                                      diType         := SOCKET_STREAM,
                                      diProtocol     := SOCKET_IPPROTO_TCP,
                                      pResult        := ADR(_result) );
          IF ( _listener = RTS_INVALID_HANDLE )
          THEN
            ErrorID   := _result;
            ErrorStep := _step;
            Error     := TRUE;
            _step     := 90;
            EXIT;
          END_IF
          // the port can be opened again at once after a restart of the PLC program
          _value  := 1;
          _result := SysSockSetOption( hSocket        := _listener,
                                       diLevel        := SOCKET_SOL,
                                       diOption       := SOCKET_SO_REUSEADDR,
                                       pdiOptionValue := ADR(_value),
                                       diOptionLen    := SIZEOF(_value) );
          _value  := 1;
          _result := SysSockIoctl( hSocket      := _listener,
                                   diCommand    := SOCKET_FIONBIO,
                                   pdiParameter := ADR(_value) );
          IF ( _result = RESULT_OK )
          THEN
            _address.sin_family := SOCKET_AF_INET;
            _address.sin_port   := SysSockHtons(LocalPort);
            IF ( LEN(LocalHost) = 0 )
            THEN
              _address.sin_addr.ulAddr := SOCKET_INADDR_ANY;
            ELSE
              _host   := LocalHost;
              _result := SysSockInetAddr( szIPAddress := _host,
                                          pInAddr     := ADR(_address.sin_addr.ulAddr) );
            END_IF
          END_IF
          IF ( _result = RESULT_OK )
          THEN
            _result := SysSockBind( hSocket        := _listener,
                                    pSockAddr      := ADR(_address),
                                    diSockAddrSize := SIZEOF(_address) );
          END_IF
          IF ( _result = RESULT_OK )
          THEN
            _result := SysSockListen( hSocket          := _listener,
                                      diMaxConnections := 1 );
          END_IF
          IF ( _result <> RESULT_OK )
          THEN
            ErrorID   := _result;
            ErrorStep := _step;
            Error     := TRUE;
            SysSockClose(hSocket := _listener);
            _listener := RTS_INVALID_HANDLE;
            _step     := 90;
            EXIT;
          END_IF
          _step := 20;

      20: // wait for a client (poll, non-blocking)
          _addressSize := SIZEOF(_clientAddress);
          _newSocket   := SysSockAccept( hSocket         := _listener,
                                         pSockAddr       := ADR(_clientAddress),
                                         pdiSockAddrSize := ADR(_addressSize),
                                         pResult         := ADR(_result) );
          IF ( _newSocket <> RTS_INVALID_HANDLE )
          THEN
            _socket    := _newSocket;
            _newSocket := RTS_INVALID_HANDLE;
            _step      := 25;
          ELSIF (( _result <> RESULT_OK         ) AND
                 ( _result <> RESULT_WOULDBLOCK ))
          THEN
            ErrorID   := _result;
            ErrorStep := _step;
            Error     := TRUE;
            _step     := 80;
          ELSE
            // no client yet
            EXIT;
          END_IF

      25: // new connection: non-blocking, no Nagle delay (one small telegram per cycle)
          _value  := 1;
          _result := SysSockIoctl( hSocket      := _socket,
                                   diCommand    := SOCKET_FIONBIO,
                                   pdiParameter := ADR(_value) );
          _value  := 1;
          SysSockSetOption( hSocket        := _socket,
                            diLevel        := SOCKET_IPPROTO_TCP,
                            diOption       := SOCKET_TCP_NODELAY,
                            pdiOptionValue := ADR(_value),
                            diOptionLen    := SIZEOF(_value) );
          IF ( _result <> RESULT_OK )
          THEN
            ErrorID   := _result;
            ErrorStep := _step;
            Error     := TRUE;
            _step     := 70;
          ELSE
            Error        := FALSE;
            ErrorID      := 0;
            ErrorStep    := 0;
            Connections  := Connections + 1;
            MaxInterval  := T#0S;
            Interval     := T#0S;
            _lastRequest := TIME();
            _rxCount     := 0;
            _step        := 30;
          END_IF

      30: // a new client replaces the connected one (e.g. Python reconnects after a timeout,
          // or the old connection is half open after a cable break)
          _addressSize := SIZEOF(_clientAddress);
          _newSocket   := SysSockAccept( hSocket         := _listener,
                                         pSockAddr       := ADR(_clientAddress),
                                         pdiSockAddrSize := ADR(_addressSize),
                                         pResult         := ADR(_result) );
          IF ( _newSocket <> RTS_INVALID_HANDLE )
          THEN
            _step := 70;
          ELSE
            _step := 31;
          END_IF

      31: // receive the request (possibly in several parts)
          _length := UDINT_TO_DINT(LengthPlcToRob - _rxCount);
          _count  := SysSockRecv( hSocket      := _socket,
                                  pbyBuffer    := ADR(_rxBuffer[_rxCount]),
                                  diBufferSize := _length,
                                  diFlags      := 0,
                                  pResult      := ADR(_result) );
          IF ( _count > 0 )
          THEN
            _rxCount := _rxCount + TO_UDINT(_count);
            IF ( _rxCount < LengthPlcToRob )
            THEN
              // rest of the request in the next cycle
              _step := 30;
              EXIT;
            END_IF
            // complete request -> PROFINET outputs
            FOR _idx := 0 TO LengthPlcToRob - 1
            DO
              RobotOutData[LOWER_BOUND(RobotOutData, 1) + UDINT_TO_DINT(_idx)] := _rxBuffer[_idx];
            END_FOR
            NewTelegram  := TRUE;
            Telegrams    := Telegrams + 1;
            Interval     := TIME() - _lastRequest;
            _lastRequest := TIME();
            IF ( Interval > MaxInterval )
            THEN
              MaxInterval := Interval;
            END_IF
            _rxCount    := 0;
            _delayCount := 0;
            _step       := 35;
          ELSIF ( _result = RESULT_WOULDBLOCK )
          THEN
            // nothing received yet -> poll again in the next cycle
            _step := 30;
            EXIT;
          ELSE
            // 0 bytes without error: the client closed the connection; otherwise a socket error
            IF ( _result <> RESULT_OK )
            THEN
              ErrorID   := _result;
              ErrorStep := _step;
              Error     := TRUE;
            END_IF
            _step := 70;
          END_IF

      35: // wait AnswerDelayCycles PLC cycles (outputs go out, inputs come in)
          IF ( _delayCount < AnswerDelayCycles )
          THEN
            _delayCount := _delayCount + 1;
            EXIT;
          END_IF
          // answer = PROFINET inputs of this cycle
          FOR _idx := 0 TO LengthRobToPlc - 1
          DO
            _txBuffer[_idx] := RobotInData[LOWER_BOUND(RobotInData, 1) + UDINT_TO_DINT(_idx)];
          END_FOR
          _txCount := 0;
          _step    := 40;

      40: // send the answer (possibly in several parts)
          _length := UDINT_TO_DINT(LengthRobToPlc - _txCount);
          _count  := SysSockSend( hSocket      := _socket,
                                  pbyBuffer    := ADR(_txBuffer[_txCount]),
                                  diBufferSize := _length,
                                  diFlags      := 0,
                                  pResult      := ADR(_result) );
          IF ( _count > 0 )
          THEN
            _txCount := _txCount + TO_UDINT(_count);
            IF ( _txCount < LengthRobToPlc )
            THEN
              EXIT;
            END_IF
            // next request
            _step := 30;
            EXIT;
          ELSIF ( _result = RESULT_WOULDBLOCK )
          THEN
            // send buffer full -> again in the next cycle
            EXIT;
          ELSE
            ErrorID   := _result;
            ErrorStep := _step;
            Error     := TRUE;
            _step     := 70;
          END_IF

      70: // close the client socket
          SysSockClose(hSocket := _socket);
          _socket  := RTS_INVALID_HANDLE;
          _rxCount := 0;
          IF ( _shutdown OR NOT Enable )
          THEN
            // close the server as well (the new client too, if one was accepted)
            IF ( _newSocket <> RTS_INVALID_HANDLE )
            THEN
              SysSockClose(hSocket := _newSocket);
              _newSocket := RTS_INVALID_HANDLE;
            END_IF
            _step := 80;
          ELSIF ( _newSocket <> RTS_INVALID_HANDLE )
          THEN
            // continue with the new client
            _socket    := _newSocket;
            _newSocket := RTS_INVALID_HANDLE;
            _step      := 25;
          ELSE
            // wait for the next client
            _step := 20;
            EXIT;
          END_IF

      80: // close the listener
          IF ( _listener <> RTS_INVALID_HANDLE )
          THEN
            SysSockClose(hSocket := _listener);
            _listener := RTS_INVALID_HANDLE;
          END_IF
          _shutdown := FALSE;
          IF ( Error AND Enable )
          THEN
            _step := 90;
          ELSE
            _step := 0;
          END_IF
          EXIT;

      90: // error of the server: wait before the next attempt
          _timer( IN := TRUE, PT := RetryDelay );
          IF (( NOT Enable ) OR
              ( _timer.Q   ))
          THEN
            _timer( IN := FALSE );
            _step := 0;
          ELSE
            EXIT;
          END_IF

    ELSE
      ErrorID   := 16#FFFE;
      ErrorStep := _step;
      Error     := TRUE;
      _step     := 70;
    END_CASE
  END_FOR

  // states derived from the step, so they cannot differ from it
  Listening := ( _step >= 20 ) AND ( _step < 80 );
  Connected := ( _step >= 25 ) AND ( _step < 70 );

END_FUNCTION_BLOCK


/// Closes the sockets when the application is reset, downloaded or stopped (CODESYS keeps them open otherwise)
METHOD FB_exit : BOOL
VAR_INPUT
  /// TRUE: called for the old instance during an online change (the sockets stay with the new instance)
  bInCopyCode : BOOL;
END_VAR

  IF ( NOT bInCopyCode )
  THEN
    IF ( _socket <> RTS_INVALID_HANDLE )
    THEN
      SysSockClose(hSocket := _socket);
      _socket := RTS_INVALID_HANDLE;
    END_IF
    IF ( _newSocket <> RTS_INVALID_HANDLE )
    THEN
      SysSockClose(hSocket := _newSocket);
      _newSocket := RTS_INVALID_HANDLE;
    END_IF
    IF ( _listener <> RTS_INVALID_HANDLE )
    THEN
      SysSockClose(hSocket := _listener);
      _listener := RTS_INVALID_HANDLE;
    END_IF
  END_IF
  FB_exit := TRUE;

END_METHOD
