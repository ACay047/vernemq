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

-module(vmq_ssl).
-include_lib("public_key/include/public_key.hrl").
-include_lib("kernel/include/logger.hrl").

-export([
    socket_to_common_name/1,
    cert_to_common_name/1,
    client_cert/1,
    opts/1
]).
-export_type([client_cert/0]).

-type client_cert() :: #'OTPCertificate'{}.

client_cert(Socket) ->
    case ssl:peercert(Socket) of
        {error, no_peercert} ->
            undefined;
        {ok, Cert} ->
            Cert
    end.

socket_to_common_name(Socket) ->
    case ssl:peercert(Socket) of
        {error, no_peercert} ->
            undefined;
        {ok, Cert} ->
            OTPCert = public_key:pkix_decode_cert(Cert, otp),
            TBSCert = OTPCert#'OTPCertificate'.tbsCertificate,
            Subject = TBSCert#'OTPTBSCertificate'.subject,
            extract_cn(Subject)
    end.

cert_to_common_name(Cert) ->
    case Cert of
        undefined ->
            undefined;
        _ ->
            OTPCert = public_key:pkix_decode_cert(Cert, otp),
            TBSCert = OTPCert#'OTPCertificate'.tbsCertificate,
            Subject = TBSCert#'OTPTBSCertificate'.subject,
            extract_cn(Subject)
    end.

-spec extract_cn({'rdnSequence', list()}) -> undefined | binary().
extract_cn({rdnSequence, List}) ->
    extract_cn2(List).

-spec extract_cn2(list()) -> undefined | list().
extract_cn2([
    [
        #'AttributeTypeAndValue'{
            type = ?'id-at-commonName',
            value = {utf8String, CN}
        }
    ]
    | _
]) ->
    list_to_binary(unicode:characters_to_list(CN));
extract_cn2([
    [
        #'AttributeTypeAndValue'{
            type = ?'id-at-commonName',
            value = {printableString, CN}
        }
    ]
    | _
]) ->
    list_to_binary(unicode:characters_to_list(CN));
extract_cn2([_ | Rest]) ->
    extract_cn2(Rest);
extract_cn2([]) ->
    undefined.

opts(certfiles, Opts) ->
    [
        {cacertfile, proplists:get_value(cafile, Opts)},
        {certfile, proplists:get_value(certfile, Opts)},
        {keyfile, proplists:get_value(keyfile, Opts)},
        {password, proplists:get_value(keypasswd, Opts, "")}
    ];
opts(cert, Opts) ->
    case {vmq_ssl_psk:psk_support_enabled(Opts), proplists:get_value(certfile, Opts)} of
        {true, undefined} -> [];
        {true, _} -> opts(certfiles, Opts);
        {false, _} -> opts(certfiles, Opts)
    end.

opts(Opts) ->
    opts(cert, Opts) ++
        vmq_ssl_psk:opts(Opts) ++
        [
            {ciphers,
                ciphersuite_transform(
                    proplists:get_value(tls_version, Opts, ['tlsv1.2']),
                    proplists:get_value(ciphers, Opts, []),
                    Opts
                )},
            {eccs, proplists:get_value(eccs, Opts, ssl:eccs())},
            {fail_if_no_peer_cert,
                proplists:get_value(
                    require_certificate,
                    Opts,
                    false
                )},
            {verify,
                case
                    proplists:get_value(require_certificate, Opts, false) or
                        proplists:get_value(use_identity_as_username, Opts, false)
                of
                    true -> verify_peer;
                    _ -> verify_none
                end},
            {verify_fun, {fun verify_ssl_peer/3, proplists:get_value(crlfile, Opts, no_crl)}},
            {depth, proplists:get_value(depth, Opts, 1)},
            {versions, proplists:get_value(tls_version, Opts, ['tlsv1.2'])}
            | []
            %% TODO: support for flexible partial chain functions
            % case support_partial_chain() of
            %     true ->
            %         [{partial_chain, fun([DerCert|_]) ->
            %                                  {trusted_ca, DerCert}
            %                          end}];
            %     false ->
            %         []
            % end
        ].

ciphersuite_transform(L, [], Opts) ->
    TLSV13 = lists:member('tlsv1.3', L),
    TLS = lists:member('tlsv1.2', L) or lists:member('tlsv1.1', L) or lists:member('tlsv1', L),

    case TLSV13 of
        true -> ciphers1_3();
        false -> []
    end ++
        case TLS of
            true -> ciphers();
            false -> []
        end ++
        vmq_ssl_psk:ciphers(Opts);
ciphersuite_transform(_, CiphersString, _) when is_list(CiphersString) ->
    CiphersString.

-spec verify_ssl_peer(
    _,
    'valid'
    | 'valid_peer'
    | {'bad_cert', _}
    | {'extension', _},
    _
) ->
    {'fail',
        'is_self_signed'
        | {'bad_cert', _}}
    | {'unknown', _}
    | {'valid', _}.
verify_ssl_peer(_, {bad_cert, _} = Reason, _) ->
    {fail, Reason};
verify_ssl_peer(_, {extension, _}, UserState) ->
    {unknown, UserState};
verify_ssl_peer(_, valid, UserState) ->
    {valid, UserState};
verify_ssl_peer(Cert, valid_peer, UserState) ->
    case public_key:pkix_is_self_signed(Cert) of
        true ->
            {fail, is_self_signed};
        false ->
            check_user_state(UserState, Cert)
    end.

check_user_state(UserState, Cert) ->
    case UserState of
        no_crl ->
            {valid, UserState};
        CrlFile ->
            case vmq_crl_srv:check_crl(CrlFile, Cert) of
                true ->
                    {valid, UserState};
                false ->
                    {fail, {bad_cert, cert_revoked}}
            end
    end.

ciphers1_3() ->
    [
        "TLS_AES_256_GCM_SHA384",
        "TLS_AES_128_GCM_SHA256",
        "TLS_AES_128_CCM_SHA256",
        "TLS_AES_128_CCM_8_SHA256"
    ].

ciphers() ->
    [
        "ECDHE-ECDSA-AES256-GCM-SHA384",
        "ECDHE-RSA-AES256-GCM-SHA384",
        "ECDHE-ECDSA-AES256-SHA384",
        "ECDHE-RSA-AES256-SHA384",
        "ECDHE-ECDSA-DES-CBC3-SHA",
        "ECDH-ECDSA-AES256-GCM-SHA384",
        "ECDH-RSA-AES256-GCM-SHA384",
        "ECDH-ECDSA-AES256-SHA384",
        "ECDH-RSA-AES256-SHA384",
        "DHE-DSS-AES256-GCM-SHA384",
        "DHE-DSS-AES256-SHA256",
        "AES256-GCM-SHA384",
        "AES256-SHA256",
        "ECDHE-ECDSA-AES128-GCM-SHA256",
        "ECDHE-RSA-AES128-GCM-SHA256",
        "ECDHE-ECDSA-AES128-SHA256",
        "ECDHE-RSA-AES128-SHA256",
        "ECDH-ECDSA-AES128-GCM-SHA256",
        "ECDH-RSA-AES128-GCM-SHA256",
        "ECDH-ECDSA-AES128-SHA256",
        "ECDH-RSA-AES128-SHA256",
        "DHE-DSS-AES128-GCM-SHA256",
        "DHE-DSS-AES128-SHA256",
        "AES128-GCM-SHA256",
        "AES128-SHA256",
        "ECDHE-ECDSA-AES256-SHA",
        "ECDHE-RSA-AES256-SHA",
        "DHE-DSS-AES256-SHA",
        "ECDH-ECDSA-AES256-SHA",
        "ECDH-RSA-AES256-SHA",
        "AES256-SHA",
        "ECDHE-ECDSA-AES128-SHA",
        "ECDHE-RSA-AES128-SHA",
        "DHE-DSS-AES128-SHA",
        "ECDH-ECDSA-AES128-SHA",
        "ECDH-RSA-AES128-SHA",
        "AES128-SHA"
    ].
