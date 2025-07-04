%% Copyright 2018 Erlio GmbH Basel Switzerland (http://erl.io)
%% Copyright 2018-2024 Octavo Labs/VerneMQ (https://vernemq.com/)
%% and Individual Contributors.
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
-module(vmq_schema).
-include_lib("kernel/include/logger.hrl").

-export([
    translate_listeners/1,
    parse_tls_list/1,
    string_to_secs/1,
    parse_list_to_term/1
]).

translate_listeners(Conf) ->
    %% cuttlefish messes up with the tree-like configuration style if
    %% it cannot find either configured values or defaults in the
    %% more specific leafs of the tree. That's why we always provide
    %% a default value and take care of them by ourselves.
    InfIntVal = fun(Name, Val1, Def) ->
        case Val1 of
            infinity -> infinity;
            undefined -> Def;
            -1 -> Def;
            Int when is_integer(Int) -> Int;
            _ -> cuttlefish:invalid(Name ++ "  should be an integer")
        end
    end,
    MPVal = fun(Name, Val2, Def) ->
        case Val2 of
            "off" -> "";
            undefined -> Def;
            S when is_list(S) -> S;
            _ -> cuttlefish:invalid(Name ++ " should be a string, is: " ++ Val2)
        end
    end,

    StrVal = fun
        (_, "", Def) -> Def;
        (_, S, _) when is_list(S) -> S;
        (_, undefined, Def) -> Def
    end,
    BoolVal = fun
        (_, B, _) when is_boolean(B) -> B;
        (_, undefined, Def) -> Def
    end,
    AtomVal = fun
        (_, A, _) when is_atom(A) -> A;
        (_, undefined, Def) -> Def
    end,
    IntVal = fun
        (_, I, _) when is_integer(I) -> I;
        (_, undefined, Def) -> Def
    end,
    SSLVersionsListVal = fun
        (_, SSLVersions, _) when is_list(SSLVersions) -> validate_sslversion(SSLVersions);
        (_, undefined, undefined) -> undefined;
        (_, undefined, Def) -> validate_sslversion(Def)
    end,
    %% Either "", meaning all known named curves are allowed]
    %% or a list like "[secp256r1,sect239k1,sect233k1]"
    ECCListVal = fun
        (_, ECCs, _) when is_list(ECCs) -> validate_eccs(ECCs);
        (_, undefined, Def) -> validate_eccs(Def)
    end,
    %% A value looking like "[3,4]" or "[3, 4]" or "3,4"
    StringIntegerListVal =
        fun
            (_, undefined, Def) ->
                Def;
            (_, Val, _) ->
                %% TODO: improve error handling here
                {ok, Term} = parse_list_to_term(Val),
                Term
        end,

    MZip = fun([H | _] = ListOfLists) ->
        %% get default size
        Size = length(H),
        ListOfLists = [L || L <- ListOfLists, length(L) == Size],
        [
            lists:reverse(
                lists:foldl(
                    fun(L, Acc) ->
                        [lists:nth(I, L) | Acc]
                    end,
                    [],
                    ListOfLists
                )
            )
         || I <- lists:seq(1, Size)
        ]
    end,

    {TCPIPs, TCPMaxConns} = lists:unzip(
        extract("listener.tcp", "max_connections", InfIntVal, Conf)
    ),
    {SSLIPs, SSLMaxConns} = lists:unzip(
        extract("listener.ssl", "max_connections", InfIntVal, Conf)
    ),
    {WSIPs, WSMaxConns} = lists:unzip(extract("listener.ws", "max_connections", InfIntVal, Conf)),
    {WS_SSLIPs, WS_SSLMaxConns} = lists:unzip(
        extract("listener.wss", "max_connections", InfIntVal, Conf)
    ),
    {VMQIPs, VMQMaxConns} = lists:unzip(
        extract("listener.vmq", "max_connections", InfIntVal, Conf)
    ),
    {VMQ_SSLIPs, VMQ_SSLMaxConns} = lists:unzip(
        extract("listener.vmqs", "max_connections", InfIntVal, Conf)
    ),
    {HTTPIPs, HTTPMaxConns} = lists:unzip(
        extract("listener.http", "max_connections", InfIntVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLMaxConns} = lists:unzip(
        extract("listener.https", "max_connections", InfIntVal, Conf)
    ),
    {TCPIPs, TCPMaxConnLifetime} = lists:unzip(
        extract("listener.tcp", "max_connection_lifetime", InfIntVal, Conf)
    ),
    {SSLIPs, SSLMaxConnLifetime} = lists:unzip(
        extract("listener.ssl", "max_connection_lifetime", InfIntVal, Conf)
    ),
    {WSIPs, WSMaxConnLifetime} = lists:unzip(
        extract("listener.ws", "max_connection_lifetime", InfIntVal, Conf)
    ),
    {WS_SSLIPs, WS_SSLMaxConnLifetime} = lists:unzip(
        extract("listener.wss", "max_connection_lifetime", InfIntVal, Conf)
    ),

    {TCPIPs, TCPNrOfAcceptors} = lists:unzip(
        extract("listener.tcp", "nr_of_acceptors", InfIntVal, Conf)
    ),
    {SSLIPs, SSLNrOfAcceptors} = lists:unzip(
        extract("listener.ssl", "nr_of_acceptors", InfIntVal, Conf)
    ),
    {WSIPs, WSNrOfAcceptors} = lists:unzip(
        extract("listener.ws", "nr_of_acceptors", InfIntVal, Conf)
    ),
    {WS_SSLIPs, WS_SSLNrOfAcceptors} = lists:unzip(
        extract("listener.wss", "nr_of_acceptors", InfIntVal, Conf)
    ),
    {VMQIPs, VMQNrOfAcceptors} = lists:unzip(
        extract("listener.vmq", "nr_of_acceptors", InfIntVal, Conf)
    ),
    {VMQ_SSLIPs, VMQ_SSLNrOfAcceptors} = lists:unzip(
        extract("listener.vmqs", "nr_of_acceptors", InfIntVal, Conf)
    ),
    {HTTPIPs, HTTPNrOfAcceptors} = lists:unzip(
        extract("listener.http", "nr_of_acceptors", InfIntVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLNrOfAcceptors} = lists:unzip(
        extract("listener.https", "nr_of_acceptors", InfIntVal, Conf)
    ),

    {SSLIPs, SSLTLSHandshakeTimeout} = lists:unzip(
        extract("listener.ssl", "tls_handshake_timeout", InfIntVal, Conf)
    ),
    {WS_SSLIPs, WS_SSLTLSHandshakeTimeout} = lists:unzip(
        extract("listener.wss", "tls_handshake_timeout", InfIntVal, Conf)
    ),
    {VMQ_SSLIPs, VMQ_SSLTLSHandshakeTimeout} = lists:unzip(
        extract("listener.vmqs", "tls_handshake_timeout", InfIntVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLTLSHandshakeTimeout} = lists:unzip(
        extract("listener.https", "tls_handshake_timeout", InfIntVal, Conf)
    ),

    {TCPIPs, TCPMountPoint} = lists:unzip(extract("listener.tcp", "mountpoint", MPVal, Conf)),
    {SSLIPs, SSLMountPoint} = lists:unzip(extract("listener.ssl", "mountpoint", MPVal, Conf)),
    {WSIPs, WSMountPoint} = lists:unzip(extract("listener.ws", "mountpoint", MPVal, Conf)),
    {WS_SSLIPs, WS_SSLMountPoint} = lists:unzip(extract("listener.wss", "mountpoint", MPVal, Conf)),
    {VMQIPs, VMQMountPoint} = lists:unzip(extract("listener.vmq", "mountpoint", MPVal, Conf)),
    {VMQ_SSLIPs, VMQ_SSLMountPoint} = lists:unzip(
        extract("listener.vmqs", "mountpoint", MPVal, Conf)
    ),

    {TCPIPs, TCPProxyProto} = lists:unzip(extract("listener.tcp", "proxy_protocol", BoolVal, Conf)),
    {WSIPs, WSProxyProto} = lists:unzip(extract("listener.ws", "proxy_protocol", BoolVal, Conf)),
    {WSIPs, WSProxyXFF} = lists:unzip(extract("listener.ws", "proxy_xff_support", BoolVal, Conf)),
    {WSIPs, WSProxyXFFTrusted} = lists:unzip(
        extract("listener.ws", "proxy_xff_trusted_intermediate", StrVal, Conf)
    ),
    {WSIPs, WSProxyXFFCN} = lists:unzip(
        extract("listener.ws", "proxy_xff_use_cn_as_username", BoolVal, Conf)
    ),
    {WSIPs, WSProxyXFF_CN_HEADER} = lists:unzip(
        extract("listener.ws", "proxy_xff_cn_header", StrVal, Conf)
    ),
    {HTTPIPs, HTTPProxyProto} = lists:unzip(
        extract("listener.http", "proxy_protocol", BoolVal, Conf)
    ),

    {TCPIPs, TCPAllowedProto} = lists:unzip(
        extract("listener.tcp", "allowed_protocol_versions", StringIntegerListVal, Conf)
    ),
    {SSLIPs, SSLAllowedProto} = lists:unzip(
        extract("listener.ssl", "allowed_protocol_versions", StringIntegerListVal, Conf)
    ),
    {WSIPs, WSAllowedProto} = lists:unzip(
        extract("listener.ws", "allowed_protocol_versions", StringIntegerListVal, Conf)
    ),
    {WS_SSLIPs, WS_SSLAllowedProto} = lists:unzip(
        extract("listener.wss", "allowed_protocol_versions", StringIntegerListVal, Conf)
    ),

    {TCPIPs, TCPAllowAnonymousOverride} = lists:unzip(
        extract("listener.tcp", "allow_anonymous_override", BoolVal, Conf)
    ),
    {SSLIPs, SSLAllowAnonymousOverride} = lists:unzip(
        extract("listener.ssl", "allow_anonymous_override", BoolVal, Conf)
    ),

    {TCPIPs, TCPBufferSizes} = lists:unzip(
        extract("listener.tcp", "buffer_sizes", StringIntegerListVal, Conf)
    ),
    {SSLIPs, SSLBufferSizes} = lists:unzip(
        extract("listener.ssl", "buffer_sizes", StringIntegerListVal, Conf)
    ),
    {VMQIPs, VMQBufferSizes} = lists:unzip(
        extract("listener.vmq", "buffer_sizes", StringIntegerListVal, Conf)
    ),
    {VMQIPs, VMQHighWatermarks} = lists:unzip(
        extract("listener.vmq", "high_watermark", IntVal, Conf)
    ),
    {VMQIPs, VMQHighMsgQWatermarks} = lists:unzip(
        extract("listener.vmq", "high_msgq_watermark", IntVal, Conf)
    ),
    {VMQIPs, VMQLowWatermarks} = lists:unzip(
        extract("listener.vmq", "low_watermark", IntVal, Conf)
    ),
    {VMQIPs, VMQLowMsgQWatermarks} = lists:unzip(
        extract("listener.vmq", "low_msgq_watermark", IntVal, Conf)
    ),

    {HTTPIPs, HTTPMaxLengths} = lists:unzip(
        extract("listener.http", "max_request_line_length", IntVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLMaxLengths} = lists:unzip(
        extract("listener.https", "max_request_line_length", IntVal, Conf)
    ),
    {WSIPs, WSMaxLengths} = lists:unzip(
        extract("listener.ws", "max_request_line_length", IntVal, Conf)
    ),
    {WS_SSLIPs, WS_SSLMaxLengths} = lists:unzip(
        extract("listener.wss", "max_request_line_length", IntVal, Conf)
    ),
    {HTTPIPs, HTTPHeaderLengths} = lists:unzip(
        extract("listener.http", "max_header_value_length", IntVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLHeaderLengths} = lists:unzip(
        extract("listener.https", "max_header_value_length", IntVal, Conf)
    ),
    {WSIPs, WSHeaderLengths} = lists:unzip(
        extract("listener.ws", "max_header_value_length", IntVal, Conf)
    ),
    {WS_SSLIPs, WS_SSLHeaderLengths} = lists:unzip(
        extract("listener.wss", "max_header_value_length", IntVal, Conf)
    ),

    {HTTPIPs, HTTPConfigMod} = lists:unzip(extract("listener.http", "config_mod", AtomVal, Conf)),
    {HTTPIPs, HTTPConfigFun} = lists:unzip(extract("listener.http", "config_fun", AtomVal, Conf)),
    {HTTPIPs, HTTPModules} = lists:unzip(extract("listener.http", "http_modules", StrVal, Conf)),
    {HTTPIPs, HTTPListenerName} = lists:unzip(extract_var("listener.http", "listener_name", Conf)),

    {HTTP_SSLIPs, HTTP_SSLListenerName} = lists:unzip(
        extract_var("listener.https", "listener_name", Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLConfigMod} = lists:unzip(
        extract("listener.https", "config_mod", AtomVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLConfigFun} = lists:unzip(
        extract("listener.https", "config_fun", AtomVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLHTTPModules} = lists:unzip(
        extract("listener.https", "http_modules", StrVal, Conf)
    ),
    % SSL
    {SSLIPs, SSLCAFiles} = lists:unzip(extract("listener.ssl", "cafile", StrVal, Conf)),
    {SSLIPs, SSLDepths} = lists:unzip(extract("listener.ssl", "depth", IntVal, Conf)),
    {SSLIPs, SSLCertFiles} = lists:unzip(extract("listener.ssl", "certfile", StrVal, Conf)),
    {SSLIPs, SSLCiphers} = lists:unzip(extract("listener.ssl", "ciphers", StrVal, Conf)),
    {SSLIPs, SSLECCs} = lists:unzip(extract("listener.ssl", "eccs", ECCListVal, Conf)),
    {SSLIPs, SSLCrlFiles} = lists:unzip(extract("listener.ssl", "crlfile", StrVal, Conf)),
    {SSLIPs, SSLKeyFiles} = lists:unzip(extract("listener.ssl", "keyfile", StrVal, Conf)),
    {SSLIPs, SSLKeyPasswd} = lists:unzip(extract("listener.ssl", "keypasswd", StrVal, Conf)),
    {SSLIPs, SSLRequireCerts} = lists:unzip(
        extract("listener.ssl", "require_certificate", BoolVal, Conf)
    ),
    {SSLIPs, SSLVersions} = lists:unzip(
        extract("listener.ssl", "tls_version", SSLVersionsListVal, Conf)
    ),
    {SSLIPs, SSLUseIdents} = lists:unzip(
        extract("listener.ssl", "use_identity_as_username", BoolVal, Conf)
    ),
    {SSLIPs, SSLForwardClientCerts} = lists:unzip(
        extract("listener.ssl", "forward_connection_opts", BoolVal, Conf)
    ),
    {SSLIPs, SSLPSKSupport} = lists:unzip(
        extract("listener.ssl", "psk_support", BoolVal, Conf)
    ),
    {SSLIPs, SSLPSKFile} = lists:unzip(extract("listener.ssl", "pskfile", StrVal, Conf)),
    {SSLIPs, SSLPSKFileSeparator} = lists:unzip(
        extract("listener.ssl", "pskfile_separator", StrVal, Conf)
    ),
    {SSLIPs, SSLPSKIdentityHint} = lists:unzip(
        extract("listener.ssl", "psk_identity_hint", StrVal, Conf)
    ),

    % WSS
    {WS_SSLIPs, WS_SSLCAFiles} = lists:unzip(extract("listener.wss", "cafile", StrVal, Conf)),
    {WS_SSLIPs, WS_SSLDepths} = lists:unzip(extract("listener.wss", "depth", IntVal, Conf)),
    {WS_SSLIPs, WS_SSLCertFiles} = lists:unzip(extract("listener.wss", "certfile", StrVal, Conf)),
    {WS_SSLIPs, WS_SSLCiphers} = lists:unzip(extract("listener.wss", "ciphers", StrVal, Conf)),
    {WS_SSLIPs, WS_SSLECCs} = lists:unzip(extract("listener.wss", "eccs", ECCListVal, Conf)),
    {WS_SSLIPs, WS_SSLCrlFiles} = lists:unzip(extract("listener.wss", "crlfile", StrVal, Conf)),
    {WS_SSLIPs, WS_SSLKeyFiles} = lists:unzip(extract("listener.wss", "keyfile", StrVal, Conf)),
    {WS_SSLIPs, WS_SSLKeyPasswd} = lists:unzip(extract("listener.wss", "keypasswd", StrVal, Conf)),
    {WS_SSLIPs, WS_SSLRequireCerts} = lists:unzip(
        extract("listener.wss", "require_certificate", BoolVal, Conf)
    ),
    {WS_SSLIPs, WS_SSLVersions} = lists:unzip(
        extract("listener.wss", "tls_version", SSLVersionsListVal, Conf)
    ),
    {WS_SSLIPs, WS_SSLUseIdents} = lists:unzip(
        extract("listener.wss", "use_identity_as_username", BoolVal, Conf)
    ),
    {WS_SSLIPs, WS_SSLForwardClientCerts} = lists:unzip(
        extract("listener.wss", "forward_connection_opts", BoolVal, Conf)
    ),

    % VMQS
    {VMQ_SSLIPs, VMQ_SSLCAFiles} = lists:unzip(extract("listener.vmqs", "cafile", StrVal, Conf)),
    {VMQ_SSLIPs, VMQ_SSLDepths} = lists:unzip(extract("listener.vmqs", "depth", IntVal, Conf)),
    {VMQ_SSLIPs, VMQ_SSLCertFiles} = lists:unzip(
        extract("listener.vmqs", "certfile", StrVal, Conf)
    ),
    {VMQ_SSLIPs, VMQ_SSLCiphers} = lists:unzip(extract("listener.vmqs", "ciphers", StrVal, Conf)),
    {VMQ_SSLIPs, VMQ_SSLECCs} = lists:unzip(extract("listener.vmqs", "eccs", ECCListVal, Conf)),
    {VMQ_SSLIPs, VMQ_SSLCrlFiles} = lists:unzip(extract("listener.vmqs", "crlfile", StrVal, Conf)),
    {VMQ_SSLIPs, VMQ_SSLKeyFiles} = lists:unzip(extract("listener.vmqs", "keyfile", StrVal, Conf)),
    {VMQ_SSLIPs, VMQ_SSLKeyPasswd} = lists:unzip(
        extract("listener.vmqs", "keypasswd", StrVal, Conf)
    ),
    {VMQ_SSLIPs, VMQ_SSLRequireCerts} = lists:unzip(
        extract("listener.vmqs", "require_certificate", BoolVal, Conf)
    ),
    {VMQ_SSLIPs, VMQ_SSLVersions} = lists:unzip(
        extract("listener.vmqs", "tls_version", AtomVal, Conf)
    ),
    {VMQ_SSLIPs, VMQ_SSLBufferSizes} = lists:unzip(
        extract("listener.vmqs", "buffer_sizes", StringIntegerListVal, Conf)
    ),

    % HTTPS
    {HTTP_SSLIPs, HTTP_SSLCAFiles} = lists:unzip(extract("listener.https", "cafile", StrVal, Conf)),
    {HTTP_SSLIPs, HTTP_SSLDepths} = lists:unzip(extract("listener.https", "depth", IntVal, Conf)),
    {HTTP_SSLIPs, HTTP_SSLCertFiles} = lists:unzip(
        extract("listener.https", "certfile", StrVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLCiphers} = lists:unzip(
        extract("listener.https", "ciphers", StrVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLECCs} = lists:unzip(extract("listener.https", "eccs", ECCListVal, Conf)),
    {HTTP_SSLIPs, HTTP_SSLCrlFiles} = lists:unzip(
        extract("listener.https", "crlfile", StrVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLKeyFiles} = lists:unzip(
        extract("listener.https", "keyfile", StrVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLKeyPasswd} = lists:unzip(
        extract("listener.https", "keypasswd", StrVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLRequireCerts} = lists:unzip(
        extract("listener.https", "require_certificate", BoolVal, Conf)
    ),
    {HTTP_SSLIPs, HTTP_SSLVersions} = lists:unzip(
        extract("listener.https", "tls_version", SSLVersionsListVal, Conf)
    ),

    TCP = lists:zip(
        TCPIPs,
        MZip([
            TCPMaxConns,
            TCPMaxConnLifetime,
            TCPNrOfAcceptors,
            TCPMountPoint,
            TCPProxyProto,
            TCPAllowedProto,
            TCPBufferSizes,
            TCPAllowAnonymousOverride
        ])
    ),
    WS = lists:zip(
        WSIPs,
        MZip([
            WSMaxConns,
            WSMaxConnLifetime,
            WSNrOfAcceptors,
            WSMountPoint,
            WSProxyProto,
            WSProxyXFF,
            WSProxyXFFTrusted,
            WSProxyXFFCN,
            WSProxyXFF_CN_HEADER,
            WSMaxLengths,
            WSHeaderLengths,
            WSAllowedProto
        ])
    ),
    VMQ = lists:zip(
        VMQIPs,
        MZip([
            VMQMaxConns,
            VMQNrOfAcceptors,
            VMQMountPoint,
            VMQBufferSizes,
            VMQHighWatermarks,
            VMQLowWatermarks,
            VMQHighMsgQWatermarks,
            VMQLowMsgQWatermarks
        ])
    ),
    HTTP = lists:zip(
        HTTPIPs,
        MZip([
            HTTPMaxConns,
            HTTPNrOfAcceptors,
            HTTPConfigMod,
            HTTPConfigFun,
            HTTPMaxLengths,
            HTTPHeaderLengths,
            HTTPModules,
            HTTPListenerName,
            HTTPProxyProto
        ])
    ),

    SSL = lists:zip(
        SSLIPs,
        MZip([
            SSLMaxConns,
            SSLMaxConnLifetime,
            SSLNrOfAcceptors,
            SSLTLSHandshakeTimeout,
            SSLMountPoint,
            SSLCAFiles,
            SSLDepths,
            SSLCertFiles,
            SSLCiphers,
            SSLECCs,
            SSLCrlFiles,
            SSLKeyFiles,
            SSLKeyPasswd,
            SSLRequireCerts,
            SSLVersions,
            SSLUseIdents,
            SSLForwardClientCerts,
            SSLPSKSupport,
            SSLPSKFile,
            SSLPSKFileSeparator,
            SSLPSKIdentityHint,
            SSLAllowedProto,
            SSLBufferSizes,
            SSLAllowAnonymousOverride
        ])
    ),
    WSS = lists:zip(
        WS_SSLIPs,
        MZip([
            WS_SSLMaxConns,
            WS_SSLMaxConnLifetime,
            WS_SSLNrOfAcceptors,
            WS_SSLTLSHandshakeTimeout,
            WS_SSLMountPoint,
            WS_SSLCAFiles,
            WS_SSLDepths,
            WS_SSLCertFiles,
            WS_SSLCiphers,
            WS_SSLECCs,
            WS_SSLCrlFiles,
            WS_SSLKeyFiles,
            WS_SSLKeyPasswd,
            WS_SSLRequireCerts,
            WS_SSLVersions,
            WS_SSLUseIdents,
            WS_SSLForwardClientCerts,
            WS_SSLMaxLengths,
            WS_SSLHeaderLengths,
            WS_SSLAllowedProto
        ])
    ),
    VMQS = lists:zip(
        VMQ_SSLIPs,
        MZip([
            VMQ_SSLMaxConns,
            VMQ_SSLNrOfAcceptors,
            VMQ_SSLTLSHandshakeTimeout,
            VMQ_SSLMountPoint,
            VMQ_SSLCAFiles,
            VMQ_SSLDepths,
            VMQ_SSLCertFiles,
            VMQ_SSLCiphers,
            VMQ_SSLECCs,
            VMQ_SSLCrlFiles,
            VMQ_SSLKeyFiles,
            VMQ_SSLKeyPasswd,
            VMQ_SSLRequireCerts,
            VMQ_SSLVersions,
            VMQ_SSLBufferSizes
        ])
    ),
    HTTPS = lists:zip(
        HTTP_SSLIPs,
        MZip([
            HTTP_SSLMaxConns,
            HTTP_SSLNrOfAcceptors,
            HTTP_SSLTLSHandshakeTimeout,
            HTTP_SSLCAFiles,
            HTTP_SSLDepths,
            HTTP_SSLCertFiles,
            HTTP_SSLCiphers,
            HTTP_SSLECCs,
            HTTP_SSLCrlFiles,
            HTTP_SSLKeyFiles,
            HTTP_SSLKeyPasswd,
            HTTP_SSLRequireCerts,
            HTTP_SSLVersions,
            HTTP_SSLConfigMod,
            HTTP_SSLConfigFun,
            HTTP_SSLMaxLengths,
            HTTP_SSLHeaderLengths,
            HTTP_SSLHTTPModules,
            HTTP_SSLListenerName
        ])
    ),
    DropUndef = fun(L) ->
        [{K, [I || {_, V} = I <- SubL, V /= undefined]} || {K, SubL} <- L]
    end,
    [
        {mqtt, DropUndef(TCP)},
        {mqtts, DropUndef(SSL)},
        {mqttws, DropUndef(WS)},
        {mqttwss, DropUndef(WSS)},
        {vmq, DropUndef(VMQ)},
        {vmqs, DropUndef(VMQS)},
        {http, DropUndef(HTTP)},
        {https, DropUndef(HTTPS)}
    ].

extract_var(Prefix, Suffix, Conf) ->
    NameSubPrefix = lists:flatten([Prefix, ".$name"]),
    [
        begin
            {ok, Addr} = parse_addr(StrAddr),
            _ = lists:flatten([Prefix, ".", Name, ".", Suffix]),
            AddrPort = {Addr, Port},
            {AddrPort, {list_to_atom(Suffix), Name}}
        end
     || {[_, _, Name], {StrAddr, Port}} <- lists:filter(
            fun({K, _V}) ->
                cuttlefish_variable:is_fuzzy_match(K, string:tokens(NameSubPrefix, "."))
            end,
            Conf
        ),
        not lists:member(Name, [])
    ].

extract(Prefix, Suffix, Val, Conf) ->
    Mappings = ["max_connections", "nr_of_acceptors", "mountpoint", "max_connection_lifetime"],
    ExcludeRootSuffixes =
        %% ssl listener specific
        [
            "cafile",
            "depth",
            "certfile",
            "ciphers",
            "eccs",
            "crlfile",
            "keyfile",
            "keypasswd",
            "require_certificate",
            "tls_version",
            "use_identity_as_username",
            "forward_connection_opts",
            "psk_support",
            "pskfile",
            "pskfile_separator",
            "psk_identity_hint",
            "buffer_sizes",
            "high_watermark",
            "low_watermark",
            "high_msgq_watermark",
            "low_msgq_watermark",
            "tls_handshake_timeout",
            %% http listener specific
            "config_mod",
            "config_fun",
            "http_modules",
            "max_request_line_length",
            "max_header_value_length",
            %% mqtt listener specific
            "allowed_protocol_versions",
            %% other
            "proxy_protocol",
            "proxy_xff_support",
            "proxy_xff_trusted_intermediate",
            "proxy_xff_use_cn_as_username",
            "proxy_xff_cn_header",
            "allow_anonymous_override"
        ],

    %% get default from root of the tree for listeners
    RootDefault =
        case lists:member(Suffix, ExcludeRootSuffixes) of
            true ->
                undefined;
            false ->
                cuttlefish:conf_get(lists:flatten(["listener.", Suffix]), Conf)
        end,
    Default = cuttlefish:conf_get(lists:flatten([Prefix, ".", Suffix]), Conf, RootDefault),
    %% get the name value pairs
    NameSubPrefix = lists:flatten([Prefix, ".$name"]),
    [
        begin
            Prefix4 = lists:flatten([Prefix, ".", Name, ".", Suffix]),
            V1 = Val(Name, RootDefault, undefined),
            V2 = Val(Name, RootDefault, V1),
            V3 = Val(Name, cuttlefish:conf_get(Prefix4, Conf, Default), V2),
            AddrPort =
                case Result of
                    {StrAddr, P} ->
                        {ok, Addr} = parse_addr(StrAddr),
                        {Addr, P};
                    {local, StrAddr, P} ->
                        {ok, Addr} = parse_addr("local:" ++ StrAddr),
                        {Addr, P}
                end,
            {AddrPort, {list_to_atom(Suffix), V3}}
        end
     || {[_, _, Name], Result} <- lists:filter(
            fun({K, _V}) ->
                cuttlefish_variable:is_fuzzy_match(K, string:tokens(NameSubPrefix, "."))
            end,
            Conf
        ),
        not lists:member(Name, Mappings ++ ExcludeRootSuffixes),
        Result =/= true
    ].

parse_addr(StrA) ->
    case string:split(StrA, ":") of
        ["local", DomainSocket] ->
            {ok, {local, DomainSocket}};
        _ ->
            case inet:parse_address(StrA) of
                {ok, Ip} -> {ok, Ip};
                {error, einval} -> {error, {invalid_args, [{address, StrA}]}}
            end
    end.

validate_sslversion(Versions) ->
    {ok, ParsedList} = parse_tls_list(Versions),
    ParsedList.

validate_eccs("") ->
    ssl:eccs();
validate_eccs(undefined) ->
    ssl:eccs();
validate_eccs(ECCs) ->
    KnownECCs = lists:usort(ssl:eccs()),
    SpecifiedECCs =
        case ECCs of
            [Head | _] when is_atom(Head) ->
                lists:usort(ECCs);
            [_ | _] ->
                {ok, Parsed} = parse_list_to_term(ECCs),
                lists:usort(Parsed)
        end,
    UnknownECCs = lists:subtract(SpecifiedECCs, KnownECCs),
    case UnknownECCs of
        [] ->
            SpecifiedECCs;
        [_ | _] ->
            UnknownECCsStrings = string:join([atom_to_list(U) || U <- UnknownECCs], ","),
            cuttlefish:invalid("Unknown ECC named curves: " ++ UnknownECCsStrings)
    end.

string_to_secs(S) ->
    [Entity | T] = lists:reverse(S),
    case {Entity, list_to_integer(lists:reverse(T))} of
        {$s, D} -> D;
        {$h, D} -> D * 60 * 60;
        {$d, D} -> D * 24 * 60 * 60;
        {$w, D} -> D * 7 * 24 * 60 * 60;
        {$m, D} -> D * 4 * 7 * 24 * 60 * 60;
        {$y, D} -> D * 12 * 4 * 7 * 24 * 60 * 60;
        _ -> error
    end.

parse_tls_list(Val) when is_list(Val) ->
    Values = string:tokens(Val, ","),
    try
        {ok, [convert_tls(V) || V <- Values]}
    catch
        throw:invalid_value -> {error, invalid_value}
    end.

convert_tls("tlsv1") -> 'tls_v1';
convert_tls("tlsv1.1") -> 'tlsv1.1';
convert_tls("tlsv1.2") -> 'tlsv1.2';
convert_tls("tlsv1.3") -> 'tlsv1.3';
convert_tls(_) -> throw(invalid_value).

parse_list_to_term(Val) ->
    {ok, T, _} =
        case re:run(Val, "\\[.*\\]", []) of
            nomatch ->
                erl_scan:string("[" ++ Val ++ "].");
            {match, _} ->
                erl_scan:string(Val ++ ".")
        end,
    erl_parse:parse_term(T).
