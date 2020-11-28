#!/bin/bash
#
# /usr/local/sbin/ddnsupdate.sh - update DNS recorde in MS-DNS zones
# (c)2020 Hans-Helmar Althaus <althaus@m57.de>
#
VERSION=1.0.0
# Kerberos realm
REALM="EXAMPLE.COM"
# Kerberos principal
PRINCIPAL="host/SERVER-FQDN@${REALM}"
# Kerberos keytab
KRB5_KTNAME="/etc/krb5.keytab"
# Kerberos credentials cache
KRB5CCNAME="/var/run/dhcpd/dhcpd.krb5cc"
# domain to appended to hostname
DOMAIN="example.com"
# resource records TTL
TTL="3600"
# who will own keytab
DHCPDUID="dhcpd"
DHCPDGID="dhcpd"
# my name (script name)
MYNAME="$(basename ${0})"
#
PREFIX="any-random-string"
#
NOW=$(date +%Y.%m.%d-%H:%M)

## add this to any section of your dhcpd.conf
#
#if static {
#  if known { set ClientOpt="--known-static"; 
#  } else { set ClientOpt="--unknown-static";
#  }
#} else {
#  if known { set ClientOpt="--known-dynamic"; 
#  } else { set ClientOpt="--unknown-dynamic";
#  }
#}
#
#on commit {
#  if not static {
#    set ClientIP = binary-to-ascii( 10, 8, ".", leased-address );
#    set ClientID = binary-to-ascii( 16, 8, ":", substring( hardware, 1, 6 ) );
#    set noname = concat( "dhcp-", binary-to-ascii( 10, 8, "-", leased-address ) );
#    set ClientName = pick-first-value( option host-name, host-decl-name, config-option-host-name, client-name, noname );
#    log( info, concat( "Commit: IP: ", ClientIP, " DHCID: ", ClientID, " Name: ", ClientName ) );
#    execute( "/usr/local/sbin/ddnsupdate.sh", "add", "-i", ClientIP, "-m", ClientID, "-h", ClientName, ClientOpt );
#  }
#}
#
#on release {
#  if not static {
#    set ClientIP = binary-to-ascii( 10, 8, ".", leased-address );
#    set ClientID = binary-to-ascii( 16, 8, ":", substring( hardware, 1, 6 ) );
#    log( info, concat( "Release: IP: ", ClientIP, " DHCID: ", ClientID ) );
#    execute( "/usr/local/sbin/ddnsupdate.sh", "del", "-i", ClientIP, "-m", ClientID, ClientOpt );
#  }
#}
#
#on expiry {
#  if not static {
#    set ClientIP = binary-to-ascii( 10, 8, ".", leased-address );
#    log( info, concat( "Expiry: IP: ", ClientIP ) );
#    execute( "/usr/local/sbin/ddnsupdate.sh", "del", "-i", ClientIP, ClientOpt );
#  }
#}

function _usage() {
  cat <<- EOF
	Usage:
	  ${MYNAME} add -i ip-address -h hostname -m dhcid|mac-address [-t dns-ttl] [-d] 
	  ${MYNAME} del -i ip-address -m dhcid|mac-addres [-d]
	  ${MYNAME} kinit [-d]
	
	EOF
}

function _kinit() {

  export KRB5_KTNAME KRB5CCNAME

  KRB5CCDIR=$(dirname ${KRB5CCNAME})
  if [ ! -d "${KRB5CCDIR}" ]; then
    mkdir -p ${KRB5CCDIR} || exit 1
    chown ${DHCPDUID}.${DHCPDGID} "${KRB5CCDIR}"
  fi

  if kinit -k -t "${KRB5_KTNAME}" -c "${KRB5CCNAME}" "${PRINCIPAL}"; then
    echo "${NOW}: updated token"
    chown ${DHCPDUID}.${DHCPDGID} "${KRB5CCNAME}"
    exit 0
  else
    echo "${NOW}: faileed to update token, errorcode: $?"
  fi

  exit 1
}

function _getDC() {

  if [ -z "${DC}" ]; then
    DC=$( dig +short -x $(dig +short ${1} | head -1 ) )
  fi

  if [ -n "${DC}" ]; then
    echo "${DC}"
  else
    return 1
  fi

  return 0
}

function _gentxtrr () {
  echo "$( echo "${PREFIX}-${1}-${2}" | sha256sum | cut -d ' ' -f 1 )"
  return 0
}


function _main() {

  umask 77

  case "${ACTION}" in

    add)

      if [ -z "${ClientIP}" -o -z "${ClientName}" ]; then
        _usage
        exit 1
      fi
      
      NSRV=$(_getDC ${DOMAIN} || exit 1 )

      ClientFQDN="${ClientName,,}.${DOMAIN}."
      ClientIPOLD=$(dig +short ${ClientFQDN} @${NSRV})
      ClientTXT=$(_gentxtrr ${ClientID} ${ClientFQDN} )
      if [ -n "${ClientIPOLD}" ]; then
        ClientTXTOLD=$(dig +short -t txt ${ClientFQDN} @${NSRV} | tr -cd '[:alnum:]' )
        if [ -z "${ClientTXTOLD}" ]; then
          echo "add ${ClientIP} (${ClientFQDN}) FAILED: no DHCID"
          exit 1
        fi
        if [ "${ClientTXT}" != "${ClientTXTOLD}" ]; then
          echo "add ${ClientIP} (${ClientFQDN}) FAILED: DHCID is wrong"
          exit 1
        fi
      fi

      ClientPTR=$(echo ${ClientIP} | awk -F '.' '{print $4"."$3"."$2"."$1".in-addr.arpa."}')

      export KRB5_KTNAME KRB5CCNAME

      nsupdate -g ${NSUPDFLAGS} <<- NSUPDATE
	server ${NSRV}
	realm ${REALM}
	update delete ${ClientFQDN} TXT
	update delete ${ClientFQDN} A
	update add ${ClientFQDN} ${TTL} TXT ${ClientTXT}
	update add ${ClientFQDN} ${TTL} A ${ClientIP}
	send
	update delete ${ClientPTR} PTR
	update add ${ClientPTR} ${TTL} PTR ${ClientFQDN}
	send
	NSUPDATE
      RESULT=$?

      if [ "${RESULT}" -eq 0 ]; then
        echo "add ${ClientIP} (${ClientFQDN}) succeeded"
      else
        echo "add ${ClientIP} (${ClientFQDN}) FAILED: nsupdate status ${RESULT}" 
      fi
      exit ${RESULT}
    ;;

    del)

      if [ -z "${ClientIP}" ]; then
        _usage 
        exit 1
      fi

      NSRV=$(_getDC ${DOMAIN} || exit 1 )

      ClientFQDN=$(dig +short -x ${ClientIP} @${NSRV})

      ClientTXT=$(_gentxtrr ${ClientID} ${ClientFQDN} )

      if [ -n "${ClientFQDN}" ]; then
        ClientTXTOLD=$(dig +short -t txt ${ClientFQDN} @${NSRV} | tr -cd '[:alnum:]' )
        if [ -z "${ClientTXTOLD}" ]; then
          echo "delete ${ClientIP} (${ClientFQDN}) FAILED: no DHCID"
          exit 1
        fi
        if [ "${ClientTXT}" != "${ClientTXTOLD}" ]; then
          echo "delete ${ClientIP} (${ClientFQDN}) FAILED: DHCID is wrong"
          exit 1
        fi
      else
        echo "delete ${ClientIP} FAILED: no A record" 
        exit 1
      fi

      ClientPTR=$(echo ${ClientIP} | awk -F '.' '{print $4"."$3"."$2"."$1".in-addr.arpa."}')

      export KRB5_KTNAME KRB5CCNAME

      nsupdate -g ${NSUPDFLAGS} <<- NSUPDATE
	server ${NSRV}
	realm ${REALM}
	update delete ${ClientFQDN} TXT
	update delete ${ClientFQDN} A
	send
	update delete ${ClientPTR} PTR
	send
	NSUPDATE
      RESULT=$?

      if [ "${RESULT}" -eq 0 ]; then
        echo "delete ${ClientIP} (${ClientFQDN}) succeeded"
      else
        echo "delete ${ClientIP} (${ClientFQDN}) FAILED: nsupdate status ${RESULT}"
      fi
      exit ${RESULT}

    ;;

    kinit)

      _kinit
      exit 0

    ;;

    *)

      _usage
      exit 0

    ;;

  esac
}

DEBUG=0
ACTION=${1}
shift
while [ -n "${1}" ]; do
  case "${1}" in
    -d) DEBUG=$((DEBUG++)) ;;
    -m) shift ; ClientID="${1}" ;;
    -h) shift ; ClientName="${1%%.*}" ;;
    -i) shift ; ClientIP="${1}" ;;
    -t) shift ; TTL="${1}" ;;
    --known-static) ;;
    --unknown-static) ;;
    --known-dynamic) ;;
    --unknown-dynamic) ;;
  esac
  shift
done

if [ "${DEBUG}" -eq 0 ]; then
  _main | logger -s -t ${MYNAME} &
else
  set -x
  _main
fi
