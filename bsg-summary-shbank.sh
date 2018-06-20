#!/bin/bash
# bsg-summary-shbank for RHEL5 & RHEL6 & RHEL7
# Modified on 2017/10/13
# version 2.2.1 (1.1.0)

set -u

# ########################################################################
# Globals, settings, helper functions
# ########################################################################
TOOL="bsg-summary-shbank"

LANG=C
L_ALL=C
POSIXLY_CORRECT=1
export POSIXLY_CORRECT


DATE=`/bin/date +%Y-%m%d-%H-%M-%S`
IP_DEV=`route| awk '$1=="default" { print $8}'`
IP_ADDR='no_gateway'
if [[ ${IP_DEV} != '' ]]; then
    IP_ADDR=`ifconfig ${IP_DEV} | awk '/inet addr/{print $2}'| awk -F : '{print $2}'`
fi

# ###########################################################################
# log_warn_die package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/bash/log_warn_die.sh
#   t/lib/bash/log_warn_die.sh
# ###########################################################################

set -u

BSGFUNCNAME=""
BSGDEBUGR="${BSGDEBUGR:-""}"
EXIT_STATUS=0

ts() {
   TS=$(date +%F-%T | tr ':-' '_')
   echo "$TS $*"
}

info() {
   [ ${OPT_VERBOSE:-3} -ge 3 ] && ts "$*"
}

log() {
   [ ${OPT_VERBOSE:-3} -ge 2 ] && ts "$*"
}

warn() {
   [ ${OPT_VERBOSE:-3} -ge 1 ] && ts "$*" >&2
   EXIT_STATUS=1
}

die() {
   ts "$*" >&2
   EXIT_STATUS=1
   exit 1
}

_d () {
   [ "$BSGDEBUGR" ] && echo "# $BSGFUNCNAME: $(ts "$*")" >&2
}

# ###########################################################################
# End log_warn_die package
# ###########################################################################

# ###########################################################################
# parse_options package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/bash/parse_options.sh
#   t/lib/bash/parse_options.sh
# ###########################################################################





set -u

ARGV=""           # Non-option args (probably input files)
EXT_ARGV=""       # Everything after -- (args for an external command)
HAVE_EXT_ARGV=""  # Got --, everything else is put into EXT_ARGV
OPT_ERRS=0        # How many command line option errors
OPT_VERSION=""    # If --version was specified
OPT_HELP=""       # If --help was specified
PO_DIR=""         # Directory with program option spec files

usage() {
   local file="$1"

   local usage="$(grep '^Usage: ' "$file")"
   echo ${usage}
   echo
   echo "For more information, 'man $TOOL' or 'perldoc $file'."
}

usage_or_errors() {
   local file="$1"

   if [ "$OPT_VERSION" ]; then
      local version=$(grep '^pt-[^ ]\+ [0-9]' "$file")
      echo "$version"
      return 1
   fi

   if [ "$OPT_HELP" ]; then
      usage "$file"
      echo
      echo "Command line options:"
      echo
      perl -e '
         use strict;
         use warnings FATAL => qw(all);
         my $lcol = 20;         # Allow this much space for option names.
         my $rcol = 80 - $lcol; # The terminal is assumed to be 80 chars wide.
         my $name;
         while ( <> ) {
            my $line = $_;
            chomp $line;
            if ( $line =~ s/^long:/  --/ ) {
               $name = $line;
            }
            elsif ( $line =~ s/^desc:// ) {
               $line =~ s/ +$//mg;
               my @lines = grep { $_      }
                           $line =~ m/(.{0,$rcol})(?:\s+|\Z)/g;
               if ( length($name) >= $lcol ) {
                  print $name, "\n", (q{ } x $lcol);
               }
               else {
                  printf "%-${lcol}s", $name;
               }
               print join("\n" . (q{ } x $lcol), @lines);
               print "\n";
            }
         }
      ' "$PO_DIR"/*
      echo
      echo "Options and values after processing arguments:"
      echo
      (
         cd "$PO_DIR"
         for opt in *; do
            local varname="OPT_$(echo "$opt" | tr a-z- A-Z_)"
            eval local varvalue=\$${varname}
            if ! grep -q "type:" "$PO_DIR/$opt" >/dev/null; then
               if [ "$varvalue" -a "$varvalue" = "yes" ];
                  then varvalue="TRUE"
               else
                  varvalue="FALSE"
               fi
            fi
            printf -- "  --%-30s %s" "$opt" "${varvalue:-(No value)}"
            echo
         done
      )
      return 1
   fi

   if [ ${OPT_ERRS} -gt 0 ]; then
      echo
      usage "$file"
      return 1
   fi

   return 0
}

option_error() {
   local err="$1"
   OPT_ERRS=$(($OPT_ERRS + 1))
   echo "$err" >&2
}

parse_options() {
   local file="$1"
   shift

   ARGV=""
   EXT_ARGV=""
   HAVE_EXT_ARGV=""
   OPT_ERRS=0
   OPT_VERSION=""
   OPT_HELP=""
   PO_DIR="$BSG_TMPDIR/po"

   if [ ! -d "$PO_DIR" ]; then
      mkdir "$PO_DIR"
      if [ $? -ne 0 ]; then
         echo "Cannot mkdir $PO_DIR" >&2
         exit 1
      fi
   fi

   rm -rf "$PO_DIR"/*
   if [ $? -ne 0 ]; then
      echo "Cannot rm -rf $PO_DIR/*" >&2
      exit 1
   fi

   _parse_pod "$file"  # Parse POD into program option (po) spec files
   _eval_po            # Eval po into existence with default values

   if [ $# -ge 2 ] &&  [ "$1" = "--config" ]; then
      shift  # --config
      local user_config_files="$1"
      shift  # that ^
      local IFS=","
      for user_config_file in ${user_config_files}; do
         _parse_config_files "$user_config_file"
      done
   else
      _parse_config_files "/etc/percona-toolkit/percona-toolkit.conf" "/etc/percona-toolkit/$TOOL.conf" "$HOME/.percona-toolkit.conf" "$HOME/.$TOOL.conf"
   fi

   _parse_command_line "${@:-""}"
}

_parse_pod() {
   local file="$1"

   cat "$file" | PO_DIR="$PO_DIR" perl -ne '
      BEGIN { $/ = ""; }
      next unless $_ =~ m/^=head1 OPTIONS/;
      while ( defined(my $para = <>) ) {
         last if $para =~ m/^=head1/;
         chomp;
         if ( $para =~ m/^=item --(\S+)/ ) {
            my $opt  = $1;
            my $file = "$ENV{PO_DIR}/$opt";
            open my $opt_fh, ">", $file or die "Cannot open $file: $!";
            print $opt_fh "long:$opt\n";
            $para = <>;
            chomp;
            if ( $para =~ m/^[a-z ]+:/ ) {
               map {
                  chomp;
                  my ($attrib, $val) = split(/: /, $_);
                  print $opt_fh "$attrib:$val\n";
               } split(/; /, $para);
               $para = <>;
               chomp;
            }
            my ($desc) = $para =~ m/^([^?.]+)/;
            print $opt_fh "desc:$desc.\n";
            close $opt_fh;
         }
      }
      last;
   '
}

_eval_po() {
   local IFS=":"
   for opt_spec in "$PO_DIR"/*; do
      local opt=""
      local default_val=""
      local neg=0
      local size=0
      while read key val; do
         case "$key" in
            long)
               opt=$(echo ${val} | sed 's/-/_/g' | tr '[:lower:]' '[:upper:]')
               ;;
            default)
               default_val="$val"
               ;;
            "short form")
               ;;
            type)
               [ "$val" = "size" ] && size=1
               ;;
            desc)
               ;;
            negatable)
               if [ "$val" = "yes" ]; then
                  neg=1
               fi
               ;;
            *)
               echo "Invalid attribute in $opt_spec: $line" >&2
               exit 1
         esac 
      done < "$opt_spec"

      if [ -z "$opt" ]; then
         echo "No long attribute in option spec $opt_spec" >&2
         exit 1
      fi

      if [ ${neg} -eq 1 ]; then
         if [ -z "$default_val" ] || [ "$default_val" != "yes" ]; then
            echo "Option $opt_spec is negatable but not default: yes" >&2
            exit 1
         fi
      fi

      if [ ${size} -eq 1 -a -n "$default_val" ]; then
         default_val=$(size_to_bytes ${default_val})
      fi

      eval "OPT_${opt}=${default_val}"
   done
}

_parse_config_files() {

   for config_file in "${@:-""}"; do
      test -f "$config_file" || continue

      while read config_opt; do

         echo "$config_opt" | grep '^[ ]*[^#]' >/dev/null 2>&1 || continue

         config_opt="$(echo "$config_opt" | sed -e 's/^ *//g' -e 's/ *$//g' -e 's/[ ]*=[ ]*/=/' -e 's/[ ]*#.*$//')"

         [ "$config_opt" = "" ] && continue

         if ! [ "$HAVE_EXT_ARGV" ]; then
            config_opt="--$config_opt"
         fi

         _parse_command_line "$config_opt"

      done < "$config_file"

      HAVE_EXT_ARGV=""  # reset for each file

   done
}

_parse_command_line() {
   local opt=""
   local val=""
   local next_opt_is_val=""
   local opt_is_ok=""
   local opt_is_negated=""
   local real_opt=""
   local required_arg=""
   local spec=""

   for opt in "${@:-""}"; do
      if [ "$opt" = "--" -o "$opt" = "----" ]; then
         HAVE_EXT_ARGV=1
         continue
      fi
      if [ "$HAVE_EXT_ARGV" ]; then
         if [ "$EXT_ARGV" ]; then
            EXT_ARGV="$EXT_ARGV $opt"
         else
            EXT_ARGV="$opt"
         fi
         continue
      fi

      if [ "$next_opt_is_val" ]; then
         next_opt_is_val=""
         if [ $# -eq 0 ] || [ $(expr "$opt" : "\-") -eq 1 ]; then
            option_error "$real_opt requires a $required_arg argument"
            continue
         fi
         val="$opt"
         opt_is_ok=1
      else
         if [ $(expr "$opt" : "\-") -eq 0 ]; then
            if [ -z "$ARGV" ]; then
               ARGV="$opt"
            else
               ARGV="$ARGV $opt"
            fi
            continue
         fi

         real_opt="$opt"

         if $(echo ${opt} | grep '^--no[^-]' >/dev/null); then
            local base_opt=$(echo ${opt} | sed 's/^--no//')
            if [ -f "$BSG_TMPDIR/po/$base_opt" ]; then
               opt_is_negated=1
               opt="$base_opt"
            else
               opt_is_negated=""
               opt=$(echo ${opt} | sed 's/^-*//')
            fi
         else
            if $(echo ${opt} | grep '^--no-' >/dev/null); then
               opt_is_negated=1
               opt=$(echo ${opt} | sed 's/^--no-//')
            else
               opt_is_negated=""
               opt=$(echo ${opt} | sed 's/^-*//')
            fi
         fi

         if $(echo ${opt} | grep '^[a-z-][a-z-]*=' >/dev/null 2>&1); then
            val="$(echo ${opt} | awk -F= '{print $2}')"
            opt="$(echo ${opt} | awk -F= '{print $1}')"
         fi

         if [ -f "$BSG_TMPDIR/po/$opt" ]; then
            spec="$BSG_TMPDIR/po/$opt"
         else
            spec=$(grep "^short form:-$opt\$" "$BSG_TMPDIR"/po/* | cut -d ':' -f 1)
            if [ -z "$spec"  ]; then
               option_error "Unknown option: $real_opt"
               continue
            fi
         fi

         required_arg=$(cat "$spec" | awk -F: '/^type:/{print $2}')
         if [ "$required_arg" ]; then
            if [ "$val" ]; then
               opt_is_ok=1
            else
               next_opt_is_val=1
            fi
         else
            if [ "$val" ]; then
               option_error "Option $real_opt does not take a value"
               continue
            fi 
            if [ "$opt_is_negated" ]; then
               val=""
            else
               val="yes"
            fi
            opt_is_ok=1
         fi
      fi

      if [ "$opt_is_ok" ]; then
         opt=$(cat "$spec" | grep '^long:' | cut -d':' -f2 | sed 's/-/_/g' | tr '[:lower:]' '[:upper:]')

         if grep "^type:size" "$spec" >/dev/null; then
            val=$(size_to_bytes ${val})
         fi

         eval "OPT_${opt}='$val'"

         opt=""
         val=""
         next_opt_is_val=""
         opt_is_ok=""
         opt_is_negated=""
         real_opt=""
         required_arg=""
         spec=""
      fi
   done
}

size_to_bytes() {
   local size="$1"
   echo ${size} | perl -ne '%f=(B=>1, K=>1_024, M=>1_048_576, G=>1_073_741_824, T=>1_099_511_627_776); m/^(\d+)([kMGT])?/i; print $1 * $f{uc($2 || "B")};'
}

installed () {
  command -v "$1" >/dev/null 2>&1
}

# ###########################################################################
# End parse_options package
# ###########################################################################

# ###########################################################################
# tmpdir package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/bash/tmpdir.sh
#   t/lib/bash/tmpdir.sh
# ###########################################################################


set -u

BSG_TMPDIR=""

mk_tmpdir() {
   local dir="${1:-""}"

   if [ -n "$dir" ]; then
      if [ ! -d "$dir" ]; then
         mkdir "$dir" || die "Cannot make tmpdir $dir"
      fi
      BSG_TMPDIR="$dir"
   else
      local tool="${0##*/}"
      local pid="$$"
      BSG_TMPDIR=`mktemp -d -t "${tool}.${pid}.XXXXXX"` \
         || die "Cannot make secure tmpdir"
   fi
}

rm_tmpdir() {
   if [ -n "$BSG_TMPDIR" ] && [ -d "$BSG_TMPDIR" ]; then
      rm -rf "$BSG_TMPDIR"
   fi
   BSG_TMPDIR=""
}

# ###########################################################################
# End tmpdir package
# ###########################################################################

# ###########################################################################
# alt_cmds package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/bash/alt_cmds.sh
#   t/lib/bash/alt_cmds.sh
# ###########################################################################


set -u

_seq() {
   local i="$1"
   awk "BEGIN { for(i=1; i<=$i; i++) print i; }"
}

_pidof() {
   local cmd="$1"
   if ! pidof "$cmd" 2>/dev/null; then
      ps -eo pid,ucomm | awk -v comm="$cmd" '$2 == comm { print $1 }'
   fi
}

_lsof() {
   local pid="$1"
   if ! lsof -p ${pid} 2>/dev/null; then
      /bin/ls -l /proc/${pid}/fd 2>/dev/null
   fi
}



_which() {
   if [ -x /usr/bin/which ]; then
      /usr/bin/which "$1" 2>/dev/null | awk '{print $1}'
   elif which which 1>/dev/null 2>&1; then
      which "$1" 2>/dev/null | awk '{print $1}'
   else
      echo "$1"
   fi
}

# ###########################################################################
# End alt_cmds package
# ###########################################################################

# ###########################################################################
# summary_common package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/bash/summary_common.sh
#   t/lib/bash/summary_common.sh
# ###########################################################################


set -u

CMD_FILE="$( _which file 2>/dev/null )"
CMD_NM="$( _which nm 2>/dev/null )"
CMD_TAR="$( _which tar 2>/dev/null )"
CMD_OBJDUMP="$( _which objdump 2>/dev/null )"

get_nice_of_pid () {
   local pid="$1"
   local niceness="$(ps -p ${pid} -o nice | awk '$1 !~ /[^0-9]/ {print $1; exit}')"

   if [ -n "${niceness}" ]; then
      echo ${niceness}
   else
      local tmpfile="$BSG_TMPDIR/nice_through_c.tmp.c"
      _d "Getting the niceness from ps failed, somehow. We are about to try this:"
      cat <<EOC > "$tmpfile"

int main(void) {
   int priority = getpriority(PRIO_PROCESS, ${pid});
   if ( priority == -1 && errno == ESRCH ) {
      return 1;
   }
   else {
      printf("%d\\n", priority);
      return 0;
   }
}

EOC
      local c_comp=$(_which gcc)
      if [ -z "${c_comp}" ]; then
         c_comp=$(_which cc)
      fi
      _d "$tmpfile: $( cat "$tmpfile" )"
      _d "$c_comp -xc \"$tmpfile\" -o \"$tmpfile\" && eval \"$tmpfile\""
      ${c_comp} -xc "$tmpfile" -o "$tmpfile" 2>/dev/null && eval "${tmpfile}" 2>/dev/null
      if [ $? -ne 0 ]; then
         echo "?"
         _d "Failed to get a niceness value for $pid"
      fi
   fi
}

get_oom_of_pid () {
   local pid="$1"
   local oom_adj=""

   if [ -n "${pid}" -a -e /proc/cpuinfo ]; then
      if [ -s "/proc/$pid/oom_score_adj" ]; then
         oom_adj=$(cat "/proc/$pid/oom_score_adj" 2>/dev/null)
         _d "For $pid, the oom value is $oom_adj, retreived from oom_score_adj"
      else
         oom_adj=$(cat "/proc/$pid/oom_adj" 2>/dev/null)
         _d "For $pid, the oom value is $oom_adj, retreived from oom_adj"
      fi
   fi

   if [ -n "${oom_adj}" ]; then
      echo "${oom_adj}"
   else
      echo "?"
      _d "Can't find the oom value for $pid"
   fi
}

has_symbols () {
   local executable="$(_which "$1")"
   local has_symbols=""

   if    [ "${CMD_FILE}" ] \
      && [ "$(${CMD_FILE} "${executable}" | grep 'not stripped' )" ]; then
      has_symbols=1
   elif    [ "${CMD_NM}" ] \
        || [ "${CMD_OBJDMP}" ]; then
      if    [ "${CMD_NM}" ] \
         && [ !"$("${CMD_NM}" -- "${executable}" 2>&1 | grep 'File format not recognized' )" ]; then
         if [ -z "$( ${CMD_NM} -- "${executable}" 2>&1 | grep ': no symbols' )" ]; then
            has_symbols=1
         fi
      elif [ -z "$("${CMD_OBJDUMP}" -t -- "${executable}" | grep '^no symbols$' )" ]; then
         has_symbols=1
      fi
   fi

   if [ "${has_symbols}" ]; then
      echo "Yes"
   else
      echo "No"
   fi
}

setup_data_dir () {
   local existing_dir="$1"
   local data_dir=""
   if [ -z "$existing_dir" ]; then
      mkdir "$BSG_TMPDIR/data" || die "Cannot mkdir $BSG_TMPDIR/data"
      data_dir="$BSG_TMPDIR/data"
   else
      if [ ! -d "$existing_dir" ]; then
         mkdir "$existing_dir" || die "Cannot mkdir $existing_dir"
      elif [ "$( ls -A "$existing_dir" )" ]; then
         die "--save-samples directory isn't empty, halting."
      fi
      touch "$existing_dir/test" || die "Cannot write to $existing_dir"
      rm "$existing_dir/test"    || die "Cannot rm $existing_dir/test"
      data_dir="$existing_dir"
   fi
   echo "$data_dir"
}

get_var () {
   local varname="$1"
   local file="$2"
   awk -v pattern="${varname}" '$1 == pattern { if (length($2)) { len = length($1); print substr($0, len+index(substr($0, len+1), $2)) } }' "${file}"
}

# ###########################################################################
# End summary_common package
# ###########################################################################

# ###########################################################################
# report_formatting package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/bash/report_formatting.sh
#   t/lib/bash/report_formatting.sh
# ###########################################################################


set -u

POSIXLY_CORRECT=1
export POSIXLY_CORRECT

fuzzy_formula='
   rounded = 0;
   if (fuzzy_var <= 10 ) {
      rounded   = 1;
   }
   factor = 1;
   while ( rounded == 0 ) {
      if ( fuzzy_var <= 50 * factor ) {
         fuzzy_var = sprintf("%.0f", fuzzy_var / (5 * factor)) * 5 * factor;
         rounded   = 1;
      }
      else if ( fuzzy_var <= 100  * factor) {
         fuzzy_var = sprintf("%.0f", fuzzy_var / (10 * factor)) * 10 * factor;
         rounded   = 1;
      }
      else if ( fuzzy_var <= 250  * factor) {
         fuzzy_var = sprintf("%.0f", fuzzy_var / (25 * factor)) * 25 * factor;
         rounded   = 1;
      }
      factor = factor * 10;
   }'

fuzz () {
   awk -v fuzzy_var="$1" "BEGIN { ${fuzzy_formula} print fuzzy_var;}"
}

fuzzy_pct () {
   local pct="$(awk -v one="$1" -v two="$2" 'BEGIN{ if (two > 0) { printf "%d", one/two*100; } else {print 0} }')";
   echo "$(fuzz "${pct}")%"
}

section () {
   local str="$1"
   awk -v var="${str} _" 'BEGIN {
      line = sprintf("# %-60s", var);
      i = index(line, "_");
      x = substr(line, i);
      gsub(/[_ \t]/, "#", x);
      printf("%s%s\n", substr(line, 1, i-1), x);
   }'
}

subsection () {
   local str="$1"
   awk -v var="${str} _" 'BEGIN {
      line = sprintf("- %-45s", var);
      i = index(line, "_");
      x = substr(line, i);
      gsub(/[_ \t]/, "-", x);
      printf("%s%s\n", substr(line, 1, i-1), x);
   }'
}

NAME_VAL_LEN=12
name_val () {
   printf "%+*s | %s\n" "${NAME_VAL_LEN}" "$1" "$2"
}

shorten() {
   local num="$1"
   local prec="${2:-2}"
   local div="${3:-1024}"

   echo "$num" | awk -v prec="$prec" -v div="$div" '
      {
         num  = $1;
         unit = num >= 1125899906842624 ? "P" \
              : num >= 1099511627776    ? "T" \
              : num >= 1073741824       ? "G" \
              : num >= 1048576          ? "M" \
              : num >= 1024             ? "k" \
              :                           "";
         while ( num >= div ) {
            num /= div;
         }
         printf "%.*f%s", prec, num, unit;
      }
   '
}

group_concat () {
   sed -e '{H; $!d;}' -e 'x' -e 's/\n[[:space:]]*\([[:digit:]]*\)[[:space:]]*/, \1x/g' -e 's/[[:space:]][[:space:]]*/ /g' -e 's/, //' "${1}"
}

# ###########################################################################
# End report_formatting package
# ###########################################################################

# ###########################################################################
# collect_system_info package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/bash/collect_system_info.sh
#   t/lib/bash/collect_system_info.sh
# ###########################################################################



set -u

setup_commands () {
   CMD_SYSCTL="$(_which sysctl 2>/dev/null )"
   CMD_DMIDECODE="$(_which dmidecode 2>/dev/null )"
   CMD_ZONENAME="$(_which zonename 2>/dev/null )"
   CMD_DMESG="$(_which dmesg 2>/dev/null )"
   CMD_FILE="$(_which file 2>/dev/null )"
   CMD_LSPCI="$(_which lspci 2>/dev/null )"
   CMD_PRTDIAG="$(_which prtdiag 2>/dev/null )"
   CMD_SMBIOS="$(_which smbios 2>/dev/null )"
   CMD_GETENFORCE="$(_which getenforce 2>/dev/null )"
   CMD_PRTCONF="$(_which prtconf 2>/dev/null )"
   CMD_LVS="$(_which lvs 2>/dev/null)"
   CMD_VGS="$(_which vgs 2>/dev/null)"
   CMD_PVS="$(_which pvs 2>/dev/null)"
   CMD_PRSTAT="$(_which prstat 2>/dev/null)"
   CMD_ISAINFO="$(_which isainfo 2>/dev/null)"
   CMD_TOP="$(_which top 2>/dev/null)"
   CMD_ARCCONF="$( _which arcconf 2>/dev/null )"
   CMD_HPACUCLI="$( _which hpacucli 2>/dev/null )"
   CMD_HPSSACLI="$( _which hpssacli 2>/dev/null )"
   CMD_MEGACLI64="$( _which MegaCli64 2>/dev/null )"
   CMD_VMSTAT="$(_which vmstat 2>/dev/null)"
   CMD_IP="$( _which ip 2>/dev/null )"
   CMD_NETSTAT="$( _which netstat 2>/dev/null )"
   CMD_PSRINFO="$( _which psrinfo 2>/dev/null )"
   CMD_SWAPCTL="$( _which swapctl 2>/dev/null )"
   CMD_LSB_RELEASE="$( _which lsb_release 2>/dev/null )"
   CMD_ETHTOOL="$( _which ethtool 2>/dev/null )"
   CMD_GETCONF="$( _which getconf 2>/dev/null )"
   CMD_FIO_STATUS="$( _which fio-status 2>/dev/null )"
}

collect_system_data () { local BSGFUNCNAME=collect_system_data;
   local data_dir="$1"

   if [ -r /var/log/dmesg -a -s /var/log/dmesg ]; then
      cat "/var/log/dmesg" > "$data_dir/dmesg_file"
   fi

   ${CMD_SYSCTL} -a > "$data_dir/sysctl" 2>/dev/null

   if [ "${CMD_LSPCI}" ]; then
      ${CMD_LSPCI} > "$data_dir/lspci_file" 2>/dev/null
   fi

   local platform="$(uname -s)"
   echo "platform    $platform"   >> "$data_dir/summary"
   echo "hostname    $HOSTNAME" >> "$data_dir/summary"
   uptime >> "$data_dir/uptime"

   processor_info "${platform}" "$data_dir"
   find_release_and_kernel "$platform" >> "$data_dir/summary"
   cpu_and_os_arch "$platform"         >> "$data_dir/summary"
   find_virtualization "$platform" "$data_dir/dmesg_file" "$data_dir/lspci_file" >> "$data_dir/summary"
   dmidecode_system_info               >> "$data_dir/summary"

   if [ "${platform}" = "SunOS" -a "${CMD_ZONENAME}" ]; then
      echo "zonename    $(${CMD_ZONENAME})" >> "$data_dir/summary"
   fi

   if [ -x /lib/libc.so.6 ]; then
      echo "compiler    $(/lib/libc.so.6 | grep 'Compiled by' | cut -c13-)" >> "$data_dir/summary"
   fi

   local rss=$(ps -eo rss 2>/dev/null | awk '/[0-9]/{total += $1 * 1024} END {print total}')
   echo "rss    ${rss}" >> "$data_dir/summary"

   [ "$CMD_DMIDECODE" ] && ${CMD_DMIDECODE} > "$data_dir/dmidecode" 2>/dev/null

   find_memory_stats "$platform" > "$data_dir/memory"
   [ "$OPT_SUMMARIZE_MOUNTS" ] && mounted_fs_info "$platform" > "$data_dir/mounted_fs"
   raid_controller   "$data_dir/dmesg_file" "$data_dir/lspci_file" >> "$data_dir/summary"

   local controller="$(get_var raid_controller "$data_dir/summary")"
   propietary_raid_controller "$data_dir/raid-controller" "$data_dir/summary" "$data_dir" "$controller"

   [ "${platform}" = "Linux" ] && linux_exclusive_collection "$data_dir"

   if [ "$CMD_IP" -a "$OPT_SUMMARIZE_NETWORK" ]; then
      ${CMD_IP} -s link > "$data_dir/ip"
      network_device_info "$data_dir/ip" > "$data_dir/network_devices"
   fi

   [ "$CMD_SWAPCTL" ] && ${CMD_SWAPCTL} -s > "$data_dir/swapctl"

   if [ "$OPT_SUMMARIZE_PROCESSES" ]; then
      top_processes "${platform}" > "$data_dir/processes"
      notable_processes_info > "$data_dir/notable_procs"

      if [ "$CMD_VMSTAT" ]; then
         touch "$data_dir/vmstat"
         (
            ${CMD_VMSTAT} 1 ${OPT_SLEEP} > "$data_dir/vmstat"
         ) &
      fi
   fi
   
   for file in ${data_dir}/*; do
      [ "$file" = "vmstat" ] && continue
      [ ! -s "$file" ] && rm "$file"
   done
}


linux_exclusive_collection () { local BSGFUNCNAME=linux_exclusive_collection;
   local data_dir="$1"

   echo "threading    $(getconf GNU_LIBPTHREAD_VERSION)" >> "$data_dir/summary"

   local getenforce=""
   [ "$CMD_GETENFORCE" ] && getenforce="$(${CMD_GETENFORCE} 2>&1)"
   echo "getenforce    ${getenforce:-"No SELinux detected"}" >> "$data_dir/summary"

   if [ -e "$data_dir/sysctl" ]; then
      echo "swappiness    $(awk '/vm.swappiness/{print $3}' "$data_dir/sysctl")" >> "$data_dir/summary"

      local dirty_ratio="$(awk '/vm.dirty_ratio/{print $3}' "$data_dir/sysctl")"
      local dirty_bg_ratio="$(awk '/vm.dirty_background_ratio/{print $3}' "$data_dir/sysctl")"
      if [ "$dirty_ratio" -a "$dirty_bg_ratio" ]; then
         echo "dirtypolicy    $dirty_ratio, $dirty_bg_ratio" >> "$data_dir/summary"
      fi

      local dirty_bytes="$(awk '/vm.dirty_bytes/{print $3}' "$data_dir/sysctl")"
      if [ "$dirty_bytes" ]; then
         echo "dirtystatus     $(awk '/vm.dirty_bytes/{print $3}' "$data_dir/sysctl"), $(awk '/vm.dirty_background_bytes/{print $3}' "$data_dir/sysctl")" >> "$data_dir/summary"
      fi
   fi

   schedulers_and_queue_size "$data_dir/summary" > "$data_dir/partitioning"

   for file in dentry-state file-nr inode-nr; do
      echo "${file}    $(cat /proc/sys/fs/${file} 2>&1)" >> "$data_dir/summary"
   done

   [ "$CMD_LVS" -a -x "$CMD_LVS" ] && ${CMD_LVS} 1>"$data_dir/lvs" 2>"$data_dir/lvs.stderr"

   [ "$CMD_VGS" -a -x "$CMD_VGS" ] && \
      ${CMD_VGS} 2>/dev/null > "$data_dir/vgs"

   [ "$CMD_PVS" -a -x "$CMD_PVS" ] && \
      ${CMD_PVS} 2>/dev/null > "$data_dir/pvs"

   [ "$CMD_NETSTAT" -a "$OPT_SUMMARIZE_NETWORK" ] && \
      ${CMD_NETSTAT} -antp > "$data_dir/netstat" 2>/dev/null
}

network_device_info () {
   local ip_minus_s_file="$1"

   if [ "$CMD_ETHTOOL" ]; then
      local tempfile="$BSG_TMPDIR/ethtool_output_temp"
      for device in $( awk '/^[1-9]/{ print $2 }'  "$ip_minus_s_file" \
                        | awk -F: '{print $1}'     \
                        | grep -v '^lo\|^in\|^gr'  \
                        | sort -u ); do
         ethtool ${device} > "$tempfile" 2>/dev/null

         if ! grep -q 'No data available' "$tempfile"; then
            cat "$tempfile"
         fi
      done
   fi
}

find_release_and_kernel () { local BSGFUNCNAME=find_release_and_kernel;
   local platform="$1"

   local kernel=""
   local release=""
   if [ "${platform}" = "Linux" ]; then
      kernel="$(uname -r)"
      if [ -e /etc/fedora-release ]; then
         release=$(cat /etc/fedora-release);
      elif [ -e /etc/redhat-release ]; then
         release=$(cat /etc/redhat-release);
      elif [ -e /etc/system-release ]; then
         release=$(cat /etc/system-release);
      elif [ "$CMD_LSB_RELEASE" ]; then
         release="$(${CMD_LSB_RELEASE} -ds) ($(${CMD_LSB_RELEASE} -cs))"
      elif [ -e /etc/lsb-release ]; then
         release=$(grep DISTRIB_DESCRIPTION /etc/lsb-release |awk -F'=' '{print $2}' |sed 's#"##g');
      elif [ -e /etc/debian_version ]; then
         release="Debian-based version $(cat /etc/debian_version)";
         if [ -e /etc/apt/sources.list ]; then
             local code=` awk  '/^deb/ {print $3}' /etc/apt/sources.list       \
                        | awk -F/ '{print $1}'| awk 'BEGIN {FS="|"}{print $1}' \
                        | sort | uniq -c | sort -rn | head -n1 | awk '{print $2}'`
             release="${release} (${code})"
      fi
      elif ls /etc/*release >/dev/null 2>&1; then
         if grep -q DISTRIB_DESCRIPTION /etc/*release; then
            release=$(grep DISTRIB_DESCRIPTION /etc/*release | head -n1);
         else
            release=$(cat /etc/*release | head -n1);
         fi
      fi
   elif     [ "${platform}" = "FreeBSD" ] \
         || [ "${platform}" = "NetBSD"  ] \
         || [ "${platform}" = "OpenBSD" ]; then
      release="$(uname -r)"
      kernel="$(${CMD_SYSCTL} -n "kern.osrevision")"
   elif [ "${platform}" = "SunOS" ]; then
      release="$(head -n1 /etc/release)"
      if [ -z "${release}" ]; then
         release="$(uname -r)"
      fi
      kernel="$(uname -v)"
   fi
   echo "kernel    $kernel"
   echo "release    $release"
}

cpu_and_os_arch () { local BSGFUNCNAME=cpu_and_os_arch;
   local platform="$1"

   local CPU_ARCH='32-bit'
   local OS_ARCH='32-bit'
   if [ "${platform}" = "Linux" ]; then
      if grep -q ' lm ' /proc/cpuinfo; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "FreeBSD" ] || [ "${platform}" = "NetBSD" ]; then
      if ${CMD_SYSCTL} "hw.machine_arch" | grep -v 'i[36]86' >/dev/null; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "OpenBSD" ]; then
      if ${CMD_SYSCTL} "hw.machine" | grep -v 'i[36]86' >/dev/null; then
         CPU_ARCH='64-bit'
      fi
   elif [ "${platform}" = "SunOS" ]; then
      if ${CMD_ISAINFO} -b | grep 64 >/dev/null ; then
         CPU_ARCH="64-bit"
      fi
   fi
   if [ -z "$CMD_FILE" ]; then
      if [ "$CMD_GETCONF" ] && ${CMD_GETCONF} LONG_BIT 1>/dev/null 2>&1; then
         OS_ARCH="$(${CMD_GETCONF} LONG_BIT 2>/dev/null)-bit"
      else
         OS_ARCH='N/A'
      fi
   elif ${CMD_FILE} /bin/sh | grep '64-bit' >/dev/null; then
       OS_ARCH='64-bit'
   fi

   echo "CPU_ARCH    $CPU_ARCH"
   echo "OS_ARCH    $OS_ARCH"
}

find_virtualization () { local BSGFUNCNAME=find_virtualization;
   local platform="$1"
   local dmesg_file="$2"
   local lspci_file="$3"

   local tempfile="$BSG_TMPDIR/find_virtualziation.tmp"

   local virt=""
   if [ -s "$dmesg_file" ]; then
      virt="$(find_virtualization_dmesg "$dmesg_file")"
   fi
   if [ -z "${virt}" ] && [ -s "$lspci_file" ]; then
      if grep -qi "virtualbox" "$lspci_file" ; then
         virt="VirtualBox"
      elif grep -qi "vmware" "$lspci_file" ; then
         virt="VMWare"
      fi
   elif [ "${platform}" = "FreeBSD" ]; then
      if ps -o stat | grep J ; then
         virt="FreeBSD Jail"
      fi
   elif [ "${platform}" = "SunOS" ]; then
      if [ "$CMD_PRTDIAG" ] && ${CMD_PRTDIAG} > "$tempfile" 2>/dev/null; then
         virt="$(find_virtualization_generic "$tempfile" )"
      elif [ "$CMD_SMBIOS" ] && ${CMD_SMBIOS} > "$tempfile" 2>/dev/null; then
         virt="$(find_virtualization_generic "$tempfile" )"
      fi
   elif [ -e /proc/user_beancounters ]; then
      virt="OpenVZ/Virtuozzo"
   fi
   echo "virt    ${virt:-"No virtualization detected"}"
}

find_virtualization_generic() { local BSGFUNCNAME=find_virtualization_generic;
   local file="$1"
   if grep -i -e "virtualbox" "$file" >/dev/null; then
      echo "VirtualBox"
   elif grep -i -e "vmware" "$file" >/dev/null; then
      echo "VMWare"
   fi
}

find_virtualization_dmesg () { local BSGFUNCNAME=find_virtualization_dmesg;
   local file="$1"
   if grep -qi -e "vmware" -e "vmxnet" -e 'paravirtualized kernel on vmi' "${file}"; then
      echo "VMWare";
   elif grep -qi -e 'paravirtualized kernel on xen' -e 'Xen virtual console' "${file}"; then
      echo "Xen";
   elif grep -qi "qemu" "${file}"; then
      echo "QEmu";
   elif grep -qi 'paravirtualized kernel on KVM' "${file}"; then
      echo "KVM";
   elif grep -q "VBOX" "${file}"; then
      echo "VirtualBox";
   elif grep -qi 'hd.: Virtual .., ATA.*drive' "${file}"; then
      echo "Microsoft VirtualPC";
   fi
}

dmidecode_system_info () { local BSGFUNCNAME=dmidecode_system_info;
   if [ "${CMD_DMIDECODE}" ]; then
      local vendor="$(${CMD_DMIDECODE} -s "system-manufacturer" 2>/dev/null | sed 's/ *$//g')"
      echo "vendor    ${vendor}"
      if [ "${vendor}" ]; then
         local product="$(${CMD_DMIDECODE} -s "system-product-name" 2>/dev/null | sed 's/ *$//g' | sed 's/^#.*$//g')"
         local version="$(${CMD_DMIDECODE} -s "system-version" 2>/dev/null | sed 's/ *$//g' | sed 's/^#.*$//g')"
         local chassis="$(${CMD_DMIDECODE} -s "chassis-type" 2>/dev/null | sed 's/ *$//g' | sed 's/^#.*$//g')"
         local servicetag="$(${CMD_DMIDECODE} -s "system-serial-number" 2>/dev/null | sed 's/ *$//g' | sed 's/^#.*$//g')"
         local system="${vendor}; ${product}; v${version} (${chassis})"

         echo "system    ${system}"
         echo "servicetag    ${servicetag:-"Not found"}"
      fi
   fi
}

find_memory_stats () { local BSGFUNCNAME=find_memory_stats;
   local platform="$1"

   if [ "${platform}" = "Linux" ]; then
      free -b
      cat /proc/meminfo
   elif [ "${platform}" = "SunOS" ]; then
      ${CMD_PRTCONF} | awk -F: '/Memory/{print $2}'
   fi
}

mounted_fs_info () { local BSGFUNCNAME=mounted_fs_info;
   local platform="$1"

   if [ "${platform}" != "SunOS" ]; then
      local cmd="df -h"
      if [ "${platform}" = "Linux" ]; then
         cmd="df -h -P"
      fi
      ${cmd}  | sort > "$BSG_TMPDIR/mounted_fs_info.tmp"
      mount | sort | join "$BSG_TMPDIR/mounted_fs_info.tmp" -
   fi
}

raid_controller () { local BSGFUNCNAME=raid_controller;
   local dmesg_file="$1"
   local lspci_file="$2"

   local tempfile="$BSG_TMPDIR/raid_controller.tmp"

   local controller=""
   if [ -s "$lspci_file" ]; then
      controller="$(find_raid_controller_lspci "$lspci_file")"
   fi
   if [ -z "${controller}" ] && [ -s "$dmesg_file" ]; then
      controller="$(find_raid_controller_dmesg "$dmesg_file")"
   fi

   echo "raid_controller    ${controller:-"No RAID controller detected"}"
}

find_raid_controller_dmesg () { local BSGFUNCNAME=find_raid_controller_dmesg;
   local file="$1"
   local pat='scsi[0-9].*: .*'
   if grep -qi "${pat}megaraid" "${file}"; then
      echo 'LSI Logic MegaRAID SAS'
   elif grep -q "Fusion MPT SAS" "${file}"; then
      echo 'Fusion-MPT SAS'
   elif grep -q "${pat}aacraid" "${file}"; then
      echo 'AACRAID'
   elif grep -q "${pat}3ware [0-9]* Storage Controller" "${file}"; then
      echo '3Ware'
   fi
}

find_raid_controller_lspci () { local BSGFUNCNAME=find_raid_controller_lspci;
   local file="$1"
   if grep -q "RAID bus controller: LSI Logic / Symbios Logic MegaRAID SAS" "${file}" \
     || grep -q "RAID bus controller: LSI Logic / Symbios Logic LSI MegaSAS" ${file}; then
      echo 'LSI Logic MegaRAID SAS'
   elif grep -q "Fusion-MPT SAS" "${file}"; then
      echo 'Fusion-MPT SAS'
   elif grep -q "RAID bus controller: LSI Logic / Symbios Logic Unknown" "${file}"; then
      echo 'LSI Logic Unknown'
   elif grep -q "RAID bus controller: Adaptec AAC-RAID" "${file}"; then
      echo 'AACRAID'
   elif grep -q "3ware [0-9]* Storage Controller" "${file}"; then
      echo '3Ware'
   elif grep -q "Hewlett-Packard Company Smart Array" "${file}"; then
      echo 'HP Smart Array'
   elif grep -q " RAID bus controller: " "${file}"; then
      awk -F: '/RAID bus controller\:/ {print $3" "$5" "$6}' "${file}"
   fi
}

schedulers_and_queue_size () { local BSGFUNCNAME=schedulers_and_queue_size;
   local file="$1"

   local disks="$(ls /sys/block/ | grep -v -e ram -e loop -e 'fd[0-9]' | xargs echo)"
   echo "internal::disks    $disks" >> "$file"

   for disk in ${disks}; do
      if [ -e "/sys/block/${disk}/queue/scheduler" ]; then
         echo "internal::${disk}    $(cat /sys/block/${disk}/queue/scheduler | grep -o '\[.*\]') $(cat /sys/block/${disk}/queue/nr_requests)" >> "$file" 
         fdisk -l "/dev/${disk/\!//}" 2>/dev/null
      fi
   done
}

top_processes () { local BSGFUNCNAME=top_processes;
   local platform=$1

   if [ "$CMD_PRSTAT" ]; then
      ${CMD_PRSTAT} | head
   elif [ "$CMD_TOP" ]; then
      local cmd="$CMD_TOP -bn 1"
      if    [ "${platform}" = "FreeBSD" ] \
         || [ "${platform}" = "NetBSD"  ] \
         || [ "${platform}" = "OpenBSD" ]; then
         cmd="$CMD_TOP -b -d 1"
      fi
      ${cmd} \
         | sed -e 's# *$##g' -e '/./{H;$!d;}' -e 'x;/PID/!d;' \
         | grep . \
         | head
   fi
}

notable_processes_info () { local BSGFUNCNAME=notable_processes_info;
   local format="%5s    %+2d    %s\n"
   local sshd_pid=$(ps -eo pid,args | awk '$2 ~ /\/usr\/sbin\/sshd/ { print $1; exit }')

   echo "  PID    OOM    COMMAND"

   if [ "$sshd_pid" ]; then
      printf "$format" "$sshd_pid" "$(get_oom_of_pid ${sshd_pid})" "sshd"
   else
      printf "%5s    %3s    %s\n" "?" "?" "sshd doesn't appear to be running"
   fi

   local BSGDEBUGR=""
   ps -eo pid,ucomm | grep '^[0-9]' | while read pid proc; do
      [ "$sshd_pid" ] && [ "$sshd_pid" = "$pid" ] && continue
      local oom="$(get_oom_of_pid ${pid})"
      if [ "$oom" ] && [ "$oom" != "?" ] && [ "$oom" = "-17" ]; then
         printf "$format" "$pid" "$oom" "$proc"
      fi
   done
}

processor_info () { local BSGFUNCNAME=processor_info;
   local platform="$1"
   local data_dir="$2"

   if [ -f /proc/cpuinfo ]; then
      cat /proc/cpuinfo > "$data_dir/proc_cpuinfo_copy" 2>/dev/null
   elif [ "${platform}" = "SunOS" ]; then
      ${CMD_PSRINFO} -v > "$data_dir/psrinfo_minus_v"
   fi 
}

propietary_raid_controller () { local BSGFUNCNAME=propietary_raid_controller;
   local file="$1"
   local variable_file="$2"
   local data_dir="$3"
   local controller="$4"

   notfound=""
   if [ "${controller}" = "AACRAID" ]; then
      if [ -z "$CMD_ARCCONF" ]; then
         notfound="e.g. http://www.adaptec.com/en-US/support/raid/scsi_raid/ASR-2120S/"
      elif ${CMD_ARCCONF} getconfig 1 > "$file" 2>/dev/null; then
         echo "internal::raid_opt    1" >> "$variable_file"
      fi
   elif [ "${controller}" = "HP Smart Array" ]; then
      if [ "$CMD_HPACUCLI" ]; then
         if ${CMD_HPACUCLI} ctrl all show config > "$file" 2>/dev/null; then
            echo "internal::raid_opt    2" >> "$variable_file"
         fi
      elif [ "$CMD_HPSSACLI" ]; then
         if ${CMD_HPSSACLI} ctrl all show config > "$file" 2>/dev/null; then
            echo "internal::raid_opt    2" >> "$variable_file"
         fi
      else
         notfound="Not installed PSP"
      fi
   elif [ "${controller}" = "LSI Logic MegaRAID SAS" ]; then
      if [ -z "$CMD_MEGACLI64" ]; then 
         notfound="your package repository or the manufacturer's website"
      else
         echo "internal::raid_opt    3" >> "$variable_file"
         ${CMD_MEGACLI64} -AdpAllInfo -aALL -NoLog > "$data_dir/lsi_megaraid_adapter_info.tmp" 2>/dev/null
         ${CMD_MEGACLI64} -AdpBbuCmd -GetBbuStatus -aALL -NoLog > "$data_dir/lsi_megaraid_bbu_status.tmp" 2>/dev/null
         ${CMD_MEGACLI64} -LdPdInfo -aALL -NoLog > "$data_dir/lsi_megaraid_devices.tmp" 2>/dev/null
      fi
   fi

   if [ "${notfound}" ]; then
      echo "internal::raid_opt    0" >> "$variable_file"
      echo "   RAID controller software not found; try getting it from" > "$file"
      echo "   ${notfound}" >> "$file"
   fi
}

# ###########################################################################
# End collect_system_info package
# ###########################################################################

# ###########################################################################
# report_system_info package
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the Bazaar repository at,
#   lib/bash/report_system_info.sh
#   t/lib/bash/report_system_info.sh
# ###########################################################################


set -u

   
parse_proc_cpuinfo () { local BSGFUNCNAME=parse_proc_cpuinfo;
   local file="$1"
   local virtual="$(grep -c ^processor "${file}")";
   local physical="$(grep 'physical id' "${file}" | sort -u | wc -l)";
   local cores="$(grep 'cpu cores' "${file}" | head -n 1 | cut -d: -f2)";

   [ "${physical}" = "0" ] && physical="${virtual}"
   [ -z "${cores}" ] && cores=0

   cores=$((${cores} * ${physical}));
   local htt=""
   if [ ${cores} -gt 0 -a ${cores} -lt ${virtual} ]; then htt=yes; else htt=no; fi

   name_val "Processors" "physical = ${physical}, cores = ${cores}, virtual = ${virtual}, hyperthreading = ${htt}"

   awk -F: '/cpu MHz/{print $2}' "${file}" \
      | sort | uniq -c > "$BSG_TMPDIR/parse_proc_cpuinfo_cpu.unq"
   name_val "Speeds" "$(group_concat "$BSG_TMPDIR/parse_proc_cpuinfo_cpu.unq")"

   awk -F: '/model name/{print $2}' "${file}" \
      | sort | uniq -c > "$BSG_TMPDIR/parse_proc_cpuinfo_model.unq"
   name_val "Models" "$(group_concat "$BSG_TMPDIR/parse_proc_cpuinfo_model.unq")"

   awk -F: '/cache size/{print $2}' "${file}" \
      | sort | uniq -c > "$BSG_TMPDIR/parse_proc_cpuinfo_cache.unq"
   name_val "Caches" "$(group_concat "$BSG_TMPDIR/parse_proc_cpuinfo_cache.unq")"
}

parse_sysctl_cpu_freebsd() { local BSGFUNCNAME=parse_sysctl_cpu_freebsd;
   local file="$1"
   [ -e "$file" ] || return;
   local virtual="$(awk '/hw.ncpu/{print $2}' "$file")"
   name_val "Processors" "virtual = ${virtual}"
   name_val "Speeds" "$(awk '/hw.clockrate/{print $2}' "$file")"
   name_val "Models" "$(awk -F: '/hw.model/{print substr($2, 2)}' "$file")"
}

parse_sysctl_cpu_netbsd() { local BSGFUNCNAME=parse_sysctl_cpu_netbsd;
   local file="$1"

   [ -e "$file" ] || return

   local virtual="$(awk '/hw.ncpu /{print $NF}' "$file")"
   name_val "Processors" "virtual = ${virtual}"
   name_val "Models" "$(awk -F: '/hw.model/{print $3}' "$file")"
}

parse_sysctl_cpu_openbsd() { local BSGFUNCNAME=parse_sysctl_cpu_openbsd;
   local file="$1"

   [ -e "$file" ] || return

   name_val "Processors" "$(awk -F= '/hw.ncpu=/{print $2}' "$file")"
   name_val "Speeds" "$(awk -F= '/hw.cpuspeed/{print $2}' "$file")"
   name_val "Models" "$(awk -F= '/hw.model/{print substr($2, 1, index($2, " "))}' "$file")"
}

parse_psrinfo_cpus() { local BSGFUNCNAME=parse_psrinfo_cpus;
   local file="$1"

   [ -e "$file" ] || return

   name_val "Processors" "$(grep -c 'Status of .* processor' "$file")"
   awk '/operates at/ {
      start = index($0, " at ") + 4;
      end   = length($0) - start - 4
      print substr($0, start, end);
   }' "$file" | sort | uniq -c > "$BSG_TMPDIR/parse_psrinfo_cpus.tmp"
   name_val "Speeds" "$(group_concat "$BSG_TMPDIR/parse_psrinfo_cpus.tmp")"
}

parse_free_minus_b () { local BSGFUNCNAME=parse_free_minus_b;
   local file="$1"

   [ -e "$file" ] || return

   local physical=$(awk '/Mem:/{print $3}' "${file}")
   local swap_alloc=$(awk '/Swap:/{print $2}' "${file}")
   local swap_used=$(awk '/Swap:/{print $3}' "${file}")
   local virtual=$(shorten $(($physical + $swap_used)) 1)

   name_val "Total"   $(shorten $(awk '/Mem:/{print $2}' "${file}") 1)
   name_val "Free"    $(shorten $(awk '/Mem:/{print $4}' "${file}") 1)
   name_val "Used"    "physical = $(shorten ${physical} 1), swap allocated = $(shorten ${swap_alloc} 1), swap used = $(shorten ${swap_used} 1), virtual = ${virtual}"
   name_val "Buffers" $(shorten $(awk '/Mem:/{print $6}' "${file}") 1)
   name_val "Caches"  $(shorten $(awk '/Mem:/{print $7}' "${file}") 1)
   name_val "Dirty"  "$(awk '/Dirty:/ {print $2, $3}' "${file}")"
}

parse_memory_sysctl_freebsd() { local BSGFUNCNAME=parse_memory_sysctl_freebsd;
   local file="$1"

   [ -e "$file" ] || return

   local physical=$(awk '/hw.realmem:/{print $2}' "${file}")
   local mem_hw=$(awk '/hw.physmem:/{print $2}' "${file}")
   local mem_used=$(awk '
      /hw.physmem/                   { mem_hw       = $2; }
      /vm.stats.vm.v_inactive_count/ { mem_inactive = $2; }
      /vm.stats.vm.v_cache_count/    { mem_cache    = $2; }
      /vm.stats.vm.v_free_count/     { mem_free     = $2; }
      /hw.pagesize/                  { pagesize     = $2; }
      END {
         mem_inactive *= pagesize;
         mem_cache    *= pagesize;
         mem_free     *= pagesize;
         print mem_hw - mem_inactive - mem_cache - mem_free;
      }
   ' "$file");
   name_val "Total"   $(shorten ${mem_hw} 1)
   name_val "Virtual" $(shorten ${physical} 1)
   name_val "Used"    $(shorten ${mem_used} 1)
}

parse_memory_sysctl_netbsd() { local BSGFUNCNAME=parse_memory_sysctl_netbsd;
   local file="$1"
   local swapctl_file="$2"

   [ -e "$file" -a -e "$swapctl_file" ] || return

   local swap_mem="$(awk '{print $2*512}' "$swapctl_file")"
   name_val "Total"   $(shorten "$(awk '/hw.physmem /{print $NF}' "$file")" 1)
   name_val "User"    $(shorten "$(awk '/hw.usermem /{print $NF}' "$file")" 1)
   name_val "Swap"    $(shorten ${swap_mem} 1)
}

parse_memory_sysctl_openbsd() { local BSGFUNCNAME=parse_memory_sysctl_openbsd;
   local file="$1"
   local swapctl_file="$2"

   [ -e "$file" -a -e "$swapctl_file" ] || return

   local swap_mem="$(awk '{print $2*512}' "$swapctl_file")"
   name_val "Total"   $(shorten "$(awk -F= '/hw.physmem/{print $2}' "$file")" 1)
   name_val "User"    $(shorten "$(awk -F= '/hw.usermem/{print $2}' "$file")" 1)
   name_val "Swap"    $(shorten ${swap_mem} 1)
}

parse_dmidecode_mem_devices () { local BSGFUNCNAME=parse_dmidecode_mem_devices;
   local file="$1"

   [ -e "$file" ] || return

   echo "  Locator          Size     Speed             Form Factor   Type          Type Detail"
   echo "  ================ ======== ================= ============= ============= ==========="
   sed    -e '/./{H;$!d;}' \
          -e 'x;/Memory Device\n/!d;' \
          -e 's/: /:/g' \
          -e 's/</{/g' \
          -e 's/>/}/g' \
          -e 's/[ \t]*\n/\n/g' \
       "${file}" \
       | awk -F: '/Size|Type|Form.Factor|Type.Detail|[^ ]Locator/{printf("|%s", $2)}/Speed/{print "|" $2}' \
       | sed -e 's/No Module Installed/{EMPTY}/' \
       | sort \
       | awk -F'|' '{printf("  %-17s %-8s %-17s %-13s %-13s %-8s\n", $4, $2, $7, $3, $5, $6);}'
}

parse_ip_s_link () { local BSGFUNCNAME=parse_ip_s_link;
   local file="$1"

   [ -e "$file" ] || return

   echo "  interface  rx_bytes rx_packets  rx_errors   tx_bytes tx_packets  tx_errors"
   echo "  ========= ========= ========== ========== ========== ========== =========="

   awk "/^[1-9][0-9]*:/ {
      save[\"iface\"] = substr(\$2, 1, index(\$2, \":\") - 1);
      new = 1;
   }
   \$0 !~ /[^0-9 ]/ {
      if ( new == 1 ) {
         new = 0;
         fuzzy_var = \$1; ${fuzzy_formula} save[\"bytes\"] = fuzzy_var;
         fuzzy_var = \$2; ${fuzzy_formula} save[\"packs\"] = fuzzy_var;
         fuzzy_var = \$3; ${fuzzy_formula} save[\"errs\"]  = fuzzy_var;
      }
      else {
         fuzzy_var = \$1; ${fuzzy_formula} tx_bytes   = fuzzy_var;
         fuzzy_var = \$2; ${fuzzy_formula} tx_packets = fuzzy_var;
         fuzzy_var = \$3; ${fuzzy_formula} tx_errors  = fuzzy_var;
         printf \"  %-8s %10.0f %10.0f %10.0f %10.0f %10.0f %10.0f\\n\", save[\"iface\"], save[\"bytes\"], save[\"packs\"], save[\"errs\"], tx_bytes, tx_packets, tx_errors;
      }
   }" "$file"
}

parse_ethtool () {
   local file="$1"

   [ -e "$file" ] || return

   echo "  Device    Speed     Duplex"
   echo "  ========= ========= ========="


   awk '
      /^Settings for / {
         device               = substr($3, 1, index($3, ":") ? index($3, ":")-1 : length($3));
         device_names[device] = device;
      }
      /Speed:/  { devices[device ",speed"]  = $2 }
      /Duplex:/ { devices[device ",duplex"] = $2 }
      END {
         for ( device in device_names ) {
            printf("  %-10s %-10s %-10s\n",
               device,
               devices[device ",speed"],
               devices[device ",duplex"]);
         }
      }
   ' "$file"

}

parse_netstat () { local BSGFUNCNAME=parse_netstat;
   local file="$1"

   [ -e "$file" ] || return

   echo "  Connections from remote IP addresses"
   awk '$1 ~ /^tcp/ && $5 ~ /^[1-9]/ {
      print substr($5, 1, index($5, ":") - 1);
   }' "${file}" | sort | uniq -c \
      | awk "{
         fuzzy_var=\$1;
         ${fuzzy_formula}
         printf \"    %-15s %5d\\n\", \$2, fuzzy_var;
         }" \
      | sort -n -t . -k 1,1 -k 2,2 -k 3,3 -k 4,4
   echo "  Connections to local IP addresses"
   awk '$1 ~ /^tcp/ && $5 ~ /^[1-9]/ {
      print substr($4, 1, index($4, ":") - 1);
   }' "${file}" | sort | uniq -c \
      | awk "{
         fuzzy_var=\$1;
         ${fuzzy_formula}
         printf \"    %-15s %5d\\n\", \$2, fuzzy_var;
         }" \
      | sort -n -t . -k 1,1 -k 2,2 -k 3,3 -k 4,4
   echo "  Connections to top 10 local ports"
   awk '$1 ~ /^tcp/ && $5 ~ /^[1-9]/ {
      print substr($4, index($4, ":") + 1);
   }' "${file}" | sort | uniq -c | sort -rn | head -n10 \
      | awk "{
         fuzzy_var=\$1;
         ${fuzzy_formula}
         printf \"    %-15s %5d\\n\", \$2, fuzzy_var;
         }" | sort
   echo "  States of connections"
   awk '$1 ~ /^tcp/ {
      print $6;
   }' "${file}" | sort | uniq -c | sort -rn \
      | awk "{
         fuzzy_var=\$1;
         ${fuzzy_formula}
         printf \"    %-15s %5d\\n\", \$2, fuzzy_var;
         }" | sort
}

parse_filesystems () { local BSGFUNCNAME=parse_filesystems;
   local file="$1"
   local platform="$2"

   [ -e "$file" ] || return

   local spec="$(awk "
      BEGIN {
         device     = 10;
         fstype     = 4;
         options    = 4;
      }
      /./ {
         f_device     = \$1;
         f_fstype     = \$10;
         f_options    = substr(\$11, 2, length(\$11) - 2);
         if ( \"$2\" ~ /(Free|Open|Net)BSD/ ) {
            f_fstype  = substr(\$9, 2, length(\$9) - 2);
            f_options = substr(\$0, index(\$0, \",\") + 2);
            f_options = substr(f_options, 1, length(f_options) - 1);
         }
         if ( length(f_device) > device ) {
            device=length(f_device);
         }
         if ( length(f_fstype) > fstype ) {
            fstype=length(f_fstype);
         }
         if ( length(f_options) > options ) {
            options=length(f_options);
         }
      }
      END{
         print \"%-\" device \"s %5s %4s %-\" fstype \"s %-\" options \"s %s\";
      }
   " "${file}")"

   awk "
      BEGIN {
         spec=\"  ${spec}\\n\";
         printf spec, \"Filesystem\", \"Size\", \"Used\", \"Type\", \"Opts\", \"Mountpoint\";
      }
      {
         f_fstype     = \$10;
         f_options    = substr(\$11, 2, length(\$11) - 2);
         if ( \"$2\" ~ /(Free|Open|Net)BSD/ ) {
            f_fstype  = substr(\$9, 2, length(\$9) - 2);
            f_options = substr(\$0, index(\$0, \",\") + 2);
            f_options = substr(f_options, 1, length(f_options) - 1);
         }
         printf spec, \$1, \$2, \$5, f_fstype, f_options, \$6;
      }
   " "${file}"
}

parse_fdisk () { local BSGFUNCNAME=parse_fdisk;
   local file="$1"

   [ -e "$file" -a -s "$file" ] || return

   awk '
      BEGIN {
         format="%-21s %4s %10s %10s %18s\n";
         printf(format, "Device", "Type", "Start", "End", "Size");
         printf(format, "=====================", "====", "==========", "==========", "==================");
      }
      /Disk.*bytes/ {
         disk = substr($2, 1, length($2) - 1);
         size = $5;
         printf(format, disk, "Disk", "", "", size);
      }
      /Units/ {
         units = $9;
      }
      /^\/dev/ {
         if ( $2 == "*" ) {
            start = $3;
            end   = $4;
         }
         else {
            start = $2;
            end   = $3;
         }
         printf(format, $1, "Part", start, end, sprintf("%.0f", (end - start) * units));
      }
   ' "${file}"
}

parse_ethernet_controller_lspci () { local BSGFUNCNAME=parse_ethernet_controller_lspci;
   local file="$1"

   [ -e "$file" ] || return

   grep -i ethernet "${file}" | cut -d: -f3 | while read line; do
      name_val "Controller" "${line}"
   done
}

parse_hpacucli () { local BSGFUNCNAME=parse_hpacucli;
   local file="$1"
   [ -e "$file" ] || return
   grep 'logicaldrive\|physicaldrive' "${file}"
}

parse_arcconf () { local BSGFUNCNAME=parse_arcconf;
   local file="$1"

   [ -e "$file" ] || return

   local model="$(awk -F: '/Controller Model/{print $2}' "${file}")"
   local chan="$(awk -F: '/Channel description/{print $2}' "${file}")"
   local cache="$(awk -F: '/Installed memory/{print $2}' "${file}")"
   local status="$(awk -F: '/Controller Status/{print $2}' "${file}")"
   name_val "Specs" "$(echo "$model" | sed -e 's/ //'),${chan},${cache} cache,${status}"

   local battery=""
   if grep -q "ZMM" "$file"; then
      battery="$(grep -A2 'Controller ZMM Information' "$file" \
                  | awk '/Status/ {s=$4}
                         END      {printf "ZMM %s", s}')"
   else
      battery="$(grep -A5 'Controller Battery Info' "${file}" \
         | awk '/Capacity remaining/ {c=$4}
               /Status/             {s=$3}
               /Time remaining/     {t=sprintf("%dd%dh%dm", $7, $9, $11)}
               END                  {printf("%d%%, %s remaining, %s", c, t, s)}')"
   fi
   name_val "Battery" "${battery}"

   echo
   echo "  LogicalDev Size      RAID Disks Stripe Status  Cache"
   echo "  ========== ========= ==== ===== ====== ======= ======="
   for dev in $(awk '/Logical device number/{print $4}' "${file}"); do
      sed -n -e "/^Logical device .* ${dev}$/,/^$\|^Logical device number/p" "${file}" \
      | awk '
         /Logical device name/               {d=$5}
         /Size/                              {z=$3 " " $4}
         /RAID level/                        {r=$4}
         /Group [0-9]/                       {g++}
         /Stripe-unit size/                  {p=$4 " " $5}
         /Status of logical/                 {s=$6}
         /Write-cache mode.*Ena.*write-back/ {c="On (WB)"}
         /Write-cache mode.*Ena.*write-thro/ {c="On (WT)"}
         /Write-cache mode.*Disabled/        {c="Off"}
         END {
            printf("  %-10s %-9s %4d %5d %-6s %-7s %-7s\n",
               d, z, r, g, p, s, c);
         }'
   done

   echo
   echo "  PhysiclDev State   Speed         Vendor  Model        Size        Cache"
   echo "  ========== ======= ============= ======= ============ =========== ======="

   local tempresult=""
   sed -n -e '/Physical Device information/,/^$/p' "${file}" \
      | awk -F: '
         /Device #[0-9]/ {
            device=substr($0, index($0, "#"));
            devicenames[device]=device;
         }
         /Device is a/ {
            devices[device ",isa"] = substr($0, index($0, "is a") + 5);
         }
         /State/ {
            devices[device ",state"] = substr($2, 2);
         }
         /Transfer Speed/ {
            devices[device ",speed"] = substr($2, 2);
         }
         /Vendor/ {
            devices[device ",vendor"] = substr($2, 2);
         }
         /Model/ {
            devices[device ",model"] = substr($2, 2);
         }
         /Size/ {
            devices[device ",size"] = substr($2, 2);
         }
         /Write Cache/ {
            if ( $2 ~ /Enabled .write-back./ )
               devices[device ",cache"] = "On (WB)";
            else
               if ( $2 ~ /Enabled .write-th/ )
                  devices[device ",cache"] = "On (WT)";
               else
                  devices[device ",cache"] = "Off";
         }
         END {
            for ( device in devicenames ) {
               if ( devices[device ",isa"] ~ /Hard drive/ ) {
                  printf("  %-10s %-7s %-13s %-7s %-12s %-11s %-7s\n",
                     devices[device ",isa"],
                     devices[device ",state"],
                     devices[device ",speed"],
                     devices[device ",vendor"],
                     devices[device ",model"],
                     devices[device ",size"],
                     devices[device ",cache"]);
               }
            }
         }'
}

parse_fusionmpt_lsiutil () { local BSGFUNCNAME=parse_fusionmpt_lsiutil;
   local file="$1"
   echo
   awk '/LSI.*Firmware/ { print " ", $0 }' "${file}"
   grep . "${file}" | sed -n -e '/B___T___L/,$ {s/^/  /; p}'
}

parse_lsi_megaraid_adapter_info () { local BSGFUNCNAME=parse_lsi_megaraid_adapter_info;
   local file="$1"

   [ -e "$file" ] || return

   local name="$(awk -F: '/Product Name/{print substr($2, 2)}' "${file}")";
   local int=$(awk '/Host Interface/{print $4}' "${file}");
   local prt=$(awk '/Number of Backend Port/{print $5}' "${file}");
   local bbu=$(awk '/^BBU             :/{print $3}' "${file}");
   local mem=$(awk '/Memory Size/{print $4}' "${file}");
   local vdr=$(awk '/Virtual Drives/{print $4}' "${file}");
   local dvd=$(awk '/Degraded/{print $3}' "${file}");
   local phy=$(awk '/^  Disks/{print $3}' "${file}");
   local crd=$(awk '/Critical Disks/{print $4}' "${file}");
   local fad=$(awk '/Failed Disks/{print $4}' "${file}");

   name_val "Model" "${name}, ${int} interface, ${prt} ports"
   name_val "Cache" "${mem} Memory, BBU ${bbu}"
}

parse_lsi_megaraid_bbu_status () { local BSGFUNCNAME=parse_lsi_megaraid_bbu_status;
   local file="$1"

   [ -e "$file" ] || return

   local charge=$(awk '/Relative State/{print $5}' "${file}");
   local temp=$(awk '/^Temperature/{print $2}' "${file}");
   local soh=$(awk '/isSOHGood:/{print $2}' "${file}");
   name_val "BBU" "${charge}% Charged, Temperature ${temp}C, isSOHGood=${soh}"
}

format_lvs () { local BSGFUNCNAME=format_lvs;
   local file="$1"
   if [ -e "$file" ]; then
      grep -v "open failed" "$file"
   else
      echo "Unable to collect information";
   fi
}

parse_lsi_megaraid_devices () { local BSGFUNCNAME=parse_lsi_megaraid_devices;
   local file="$1"

   [ -e "$file" ] || return

   echo
   echo "  PhysiclDev Type State   Errors Vendor  Model        Size"
   echo "  ========== ==== ======= ====== ======= ============ ==========="
   for dev in $(awk '/Device Id/{print $3}' "${file}"); do
      sed -e '/./{H;$!d;}' -e "x;/Device Id: ${dev}/!d;" "${file}" \
      | awk '
         /Media Type/                        {d=substr($0, index($0, ":") + 2)}
         /PD Type/                           {t=$3}
         /Firmware state/                    {s=$3}
         /Media Error Count/                 {me=$4}
         /Other Error Count/                 {oe=$4}
         /Predictive Failure Count/          {pe=$4}
         /Inquiry Data/                      {v=$3; m=$4;}
         /Raw Size/                          {z=$3}
         END {
            printf("  %-10s %-4s %-7s %6s %-7s %-12s %-7s\n",
               substr(d, 1, 10), t, s, me "/" oe "/" pe, v, m, z);
         }'
   done
}

parse_lsi_megaraid_virtual_devices () { local BSGFUNCNAME=parse_lsi_megaraid_virtual_devices;
   local file="$1"

   [ -e "$file" ] || return

   echo
   echo "  VirtualDev Size      RAID Level Disks SpnDpth Stripe Status  Cache"
   echo "  ========== ========= ========== ===== ======= ====== ======= ========="
   awk '
      /^Virtual (Drive|Disk):/ {
         device              = $3;
         devicenames[device] = device;
      }
      /Number Of Drives/ {
         devices[device ",numdisks"] = substr($0, index($0, ":") + 1);
      }
      /^Name/ {
         devices[device ",name"] = substr($0, index($0, ":") + 1) > "" ? substr($0, index($0, ":") + 1) : "(no name)";
      }
      /RAID Level/ {
         devices[device ",primary"]   = substr($3, index($3, "-") + 1, 1);
         devices[device ",secondary"] = substr($4, index($4, "-") + 1, 1);
         devices[device ",qualifier"] = substr($NF, index($NF, "-") + 1, 1);
      }
      /Span Depth/ {
         devices[device ",spandepth"] = substr($2, index($2, ":") + 1);
      }
      /Number of Spans/ {
         devices[device ",numspans"] = $4;
      }
      /^Size/ {
         devices[device ",size"] = substr($0, index($0, ":") + 1);
      }
      /^State/ {
         devices[device ",state"] = substr($0, index($0, ":") + 2);
      }
      /^Stripe? Size/ {
         devices[device ",stripe"] = substr($0, index($0, ":") + 1);
      }
      /^Current Cache Policy/ {
         devices[device ",wpolicy"] = $4 ~ /WriteBack/ ? "WB" : "WT";
         devices[device ",rpolicy"] = $5 ~ /ReadAheadNone/ ? "no RA" : "RA";
      }
      END {
         for ( device in devicenames ) {
            raid = 0;
            if ( devices[device ",primary"] == 1 ) {
               raid = 1;
               if ( devices[device ",secondary"] == 3 ) {
                  raid = 10;
               }
            }
            else {
               if ( devices[device ",primary"] == 5 ) {
                  raid = 5;
               }
            }
            printf("  %-10s %-9s %-10s %5d %7s %6s %-7s %s\n",
               device devices[device ",name"],
               devices[device ",size"],
               raid " (" devices[device ",primary"] "-" devices[device ",secondary"] "-" devices[device ",qualifier"] ")",
               devices[device ",numdisks"],
               devices[device ",spandepth"] "-" devices[device ",numspans"],
               devices[device ",stripe"], devices[device ",state"],
               devices[device ",wpolicy"] ", " devices[device ",rpolicy"]);
         }
      }' "${file}"
}

format_vmstat () { local BSGFUNCNAME=format_vmstat;
   local file="$1"

   [ -e "$file" ] || return

   awk "
      BEGIN {
         format = \"  %2s %2s  %4s %4s %5s %5s %6s %6s %3s %3s %3s %3s %3s\n\";
      }
      /procs/ {
         print  \"  procs  ---swap-- -----io---- ---system---- --------cpu--------\";
      }
      /bo/ {
         printf format, \"r\", \"b\", \"si\", \"so\", \"bi\", \"bo\", \"ir\", \"cs\", \"us\", \"sy\", \"il\", \"wa\", \"st\";
      }
      \$0 !~ /r/ {
            fuzzy_var = \$1;   ${fuzzy_formula}  r   = fuzzy_var;
            fuzzy_var = \$2;   ${fuzzy_formula}  b   = fuzzy_var;
            fuzzy_var = \$7;   ${fuzzy_formula}  si  = fuzzy_var;
            fuzzy_var = \$8;   ${fuzzy_formula}  so  = fuzzy_var;
            fuzzy_var = \$9;   ${fuzzy_formula}  bi  = fuzzy_var;
            fuzzy_var = \$10;  ${fuzzy_formula}  bo  = fuzzy_var;
            fuzzy_var = \$11;  ${fuzzy_formula}  ir  = fuzzy_var;
            fuzzy_var = \$12;  ${fuzzy_formula}  cs  = fuzzy_var;
            fuzzy_var = \$13;                    us  = fuzzy_var;
            fuzzy_var = \$14;                    sy  = fuzzy_var;
            fuzzy_var = \$15;                    il  = fuzzy_var;
            fuzzy_var = \$16;                    wa  = fuzzy_var;
            fuzzy_var = \$17;                    st  = fuzzy_var;
            printf format, r, b, si, so, bi, bo, ir, cs, us, sy, il, wa, st;
         }
   " "${file}"
}

processes_section () { local BSGFUNCNAME=processes_section;
   local top_process_file="$1"
   local notable_procs_file="$2"


   section "Top Processes"
   cat "$top_process_file"
}

section_Processor () {
   local platform="$1"
   local data_dir="$2"

   section "Processor"

   if [ -e "$data_dir/proc_cpuinfo_copy" ]; then
      parse_proc_cpuinfo "$data_dir/proc_cpuinfo_copy"
   elif [ "${platform}" = "FreeBSD" ]; then
      parse_sysctl_cpu_freebsd "$data_dir/sysctl"
   elif [ "${platform}" = "NetBSD" ]; then
      parse_sysctl_cpu_netbsd "$data_dir/sysctl"
   elif [ "${platform}" = "OpenBSD" ]; then
      parse_sysctl_cpu_openbsd "$data_dir/sysctl"
   elif [ "${platform}" = "SunOS" ]; then
      parse_psrinfo_cpus "$data_dir/psrinfo_minus_v"
   fi
}

section_Memory () {
   local platform="$1"
   local data_dir="$2"

   section "Memory"
   if [ "${platform}" = "Linux" ]; then
      parse_free_minus_b "$data_dir/memory"
   elif [ "${platform}" = "FreeBSD" ]; then
      parse_memory_sysctl_freebsd "$data_dir/sysctl"
   elif [ "${platform}" = "NetBSD" ]; then
      parse_memory_sysctl_netbsd "$data_dir/sysctl" "$data_dir/swapctl"
   elif [ "${platform}" = "OpenBSD" ]; then
      parse_memory_sysctl_openbsd "$data_dir/sysctl" "$data_dir/swapctl"
   elif [ "${platform}" = "SunOS" ]; then
      name_val "Memory" "$(cat "$data_dir/memory")"
   fi

   if [ "${platform}" = "Linux" ]; then
      name_val "Swappiness" "$(get_var "swappiness" "$data_dir/summary")"
   fi

   if [ -s "$data_dir/dmidecode" ]; then
      parse_dmidecode_mem_devices "$data_dir/dmidecode"
   fi
}

parse_uptime () {
   local file="$1"

   awk ' / up / {
            printf substr($0, index($0, " up ")+4 );
         }
         !/ up / {
            printf $0;
         }
' "$file"
}


custom_settings (){ local BSGFUNCNAME=custom_settings;
   local data_dir="$1"
   local kernel=$(get_var "kernel" "${data_dir}/summary")
   local kernel_main_version=$(echo ${kernel} | awk -F'.el' '{print $2}' | cut -b 1)

   section "Custom Settings"

   section "RAID Controller"
   local controller="$(get_var "raid_controller" "${data_dir}/summary")"
   name_val "Controller" "$controller"
   local key="$(get_var "internal::raid_opt" "${data_dir}/summary")"
   case "$key" in
      0)
         cat "${data_dir}/raid-controller"
         ;;
      1)
         parse_arcconf "${data_dir}/raid-controller"
         ;;
      2)
         parse_hpacucli "${data_dir}/raid-controller"
         ;;
      3)
         [ -e "${data_dir}/lsi_megaraid_adapter_info.tmp" ] && \
            parse_lsi_megaraid_adapter_info "${data_dir}/lsi_megaraid_adapter_info.tmp"
         [ -e "${data_dir}/lsi_megaraid_bbu_status.tmp" ] && \
            parse_lsi_megaraid_bbu_status "${data_dir}/lsi_megaraid_bbu_status.tmp"
         if [ -e "${data_dir}/lsi_megaraid_devices.tmp" ]; then
            parse_lsi_megaraid_virtual_devices "${data_dir}/lsi_megaraid_devices.tmp"
            parse_lsi_megaraid_devices "${data_dir}/lsi_megaraid_devices.tmp"
         fi
         ;;
   esac
   
   section "Block Device ID"
   blkid | grep -E "ext3|ext4|gfs"| sort

   section "Multipath Status" 
   
   if installed multipath
   then
      local multipath="$(multipath -ll 2>/dev/null)"
   fi

   if installed powermt
   then
      local multipath="$(powermt display dev=all 2>/dev/null)"
   fi
   echo "${multipath:-Not installed multipath}"

   section "HBA Info"
   systool -c fc_host -v | sed '1d'

   section "Local Resolution"

   cat /etc/hosts

   section "Network Route"
   route -v

   section "Network Config" 
   for i in $(ls /sys/class/net)
   do
      subsection "$i" 
      ifconfig ${i}
      echo -n "${i}-"  
      ethtool ${i} | grep "Link detected" | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'
      subsection "${i} configfile"
      grep -vE "^#|^$" /etc/sysconfig/network-scripts/ifcfg-${i}
   done
   if [ -d /proc/net/bonding ]; then 
      for s in $(ls /proc/net/bonding/)
      do
         subsection "${s} status"
            cat /proc/net/bonding/${s}
      done
      else 
         subsection "bond status" 
         echo "No bonding " 
   fi
   
   section "Common Users" 
   echo "    account    :  UID   :  GID   :    HOME directory    :   shell      " 
   awk -F: '{ printf("  %-15s %-8s %-8s %-22s %-14s\n", $1, $3, $4, $6, $7); }' /etc/passwd 

   section "Users groupinfo" 
   for usrname in `awk -F: '{print $1}' /etc/passwd`;
   do
        id ${usrname} | awk '{ printf(" %-25s %-25s %-40s\n", $1, $2, $3); }'
   done

   section "Iptables" 
   iptables -L -n 

   section "NTP status" 
   
   if [ ${kernel_main_version} -lt 7 ]; then
      service ntpd status 2>&1
      echo ""
      ntpq -p 2>&1
      echo ""
      grep -E "^server" /etc/ntp.conf 2>&1
   else
      systemctl status chronyd 2>&1
      echo ""
      chronyc sources
      echo ""
      grep -E "^server" /etc/chrony.conf 2>&1
   fi

   section "Root crontab" 
   crontab -l 2>&1
   
   section "Security Police" 
   if [ ${kernel_main_version} -eq 5 ]; then
      grep -E '^PASS' /etc/login.defs
      echo ""
      grep -E 'pam_tally|pam_cracklib|pam_unix' /etc/pam.d/system-auth-ac
      echo ""
   elif [ ${kernel_main_version} -eq 6 ]; then
      grep -E '^PASS' /etc/login.defs
      echo ""
      grep -E 'pam_tally|pam_cracklib|pam_unix' /etc/pam.d/system-auth-ac
      echo ""
      grep -E 'pam_tally|pam_cracklib|pam_unix' /etc/pam.d/password-auth-ac
      echo ""
   elif [ ${kernel_main_version} -eq 7 ]; then
      grep -E 'pam_tally|pam_pwquality|pam_unix' /etc/pam.d/system-auth-ac
      echo ""
      grep -E 'pam_tally|pam_pwquality|pam_unix' /etc/pam.d/password-auth-ac
      echo ""
      grep -E 'minlen' /etc/security/pwquality.conf | grep -v -E "#"
   fi

   unset POSIXLY_CORRECT
   grep umask /etc/profile | grep -Ev '#' | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'
   grep umask /etc/bashrc | grep -Ev '#' | sed 's/^[ \t]*//g' | sed 's/[ \t]*$//g'
   export POSIXLY_CORRECT

   local tmout="$(grep TMOUT /etc/profile)"
   echo "${tmout:-No setting TMOUT}"

   grep -E "^*" /etc/security/limits.conf | grep  -E "nproc|nofile" | grep -v "#"
   grep -E "^*" /etc/security/limits.d/90-nproc.conf 2>/dev/null | grep  -E "nproc|nofile" | grep -v "#"
   grep -E "^*" /etc/security/limits.d/20-nproc.conf 2>/dev/null | grep  -E "nproc|nofile" | grep -v "#"
   echo ""

   section "Services status" 
   
   if [ ${kernel_main_version} -lt 7 ]; then
      chkconfig --list| grep -E "3:on" | grep -E "5:on"| awk '{print $1}' | while read srv
      do
         echo "-------------SERVICE $srv-------------"
         service ${srv} status
         echo "--------------------------------------"
      done
   else
      unset POSIXLY_CORRECT
      systemctl --no-legend list-unit-files --state=enabled --type=service | grep -v "@" | awk '{print $1}' | while read srv
      do
         echo "-------------SERVICE $srv-------------"
         systemctl status $srv
         echo "--------------------------------------"
      done
      export POSIXLY_CORRECT
   fi

   section "Chkconfig list" 
   #chkconfig --list | grep -E 'ntpd|snmpd|iptables|hp-health|hp-ilo|hp-snmp-agents|hpsmhd'
   if [ ${kernel_main_version} -lt 7 ]; then
      chkconfig --list | grep -E "3:on" | grep -E "5:on"
   else
      unset POSIXLY_CORRECT
      systemctl --no-legend list-unit-files --state=enabled --type=service | awk '{print $1}'
      export POSIXLY_CORRECT
   fi
   
   section "Services settings" 

   subsection "snmpd"
   if [ -f /etc/init.d/snmpd ]; then 
      grep -E "^OPTIONS" /etc/init.d/snmpd 
   fi
   
   subsection "sshd" 
   local sshd="$(grep -E "^PermitRootLogin" /etc/ssh/sshd_config)"
   echo "${sshd:-Not settings sshd}" 

   subsection "logrotate" 
   grep -E '^rotate|^compress' /etc/logrotate.conf | grep -Ev '^#' 
   if [ ${kernel_main_version} -eq 5 ]; then
      grep "\*.debug" /etc/syslog.conf
   else
      grep "\*.debug" /etc/rsyslog.conf
   fi

   section "YUM" 
   yum repolist 2>&1
   
   section "RHCS" 
   if clustat >/dev/null 2>&1; then
      clustat
      subsection "RHCS config" 
      if [ -e /etc/cluster/cluster.conf ]; then 
         grep -vE "^#|^$" /etc/cluster/cluster.conf 
         echo ""
         chkconfig --list cman  2>/dev/null
         chkconfig --list rgmanager  2>/dev/null
         chkconfig --list gfs  2>/dev/null
         chkconfig --list qdiskd  2>/dev/null
         chkconfig --list clvmd  2>/dev/null
         subsection "rc.local" 
         grep -vE "^#|^$" /etc/rc.local
      else 
         echo "No cluster config file" 
      fi
   else
      echo "Not install Cluster" 
   fi
   
   section "errlog" 

   subsection "messages" 
   local messageslog="$(grep -E "warn/error/segfault/fail/call\ trace/link\ down/critical/oom" /var/log/messages)"
   echo "${messageslog:-No error logs in system log}"  
   
   subsection "secure" 
   local securelog="$(grep -Ei "error|fail" /var/log/secure)"
   echo "${securelog:-No error logs in secure log}"  

}

save_logs () { local BSGFUNCNAME=save_logs;
   local save_file="$1"
   CMD_TAR -C /var/log -zcf ${save_file} messages

}

report_system_summary () { local BSGFUNCNAME=report_system_summary;
   local data_dir="$1"

   section "System Summary Report"

   [ -e "${data_dir}/summary" ] \
      || die "The data directory doesn't have a summary file, exiting."

   local platform="$(get_var "platform" "${data_dir}/summary")"
   name_val "UTC Date" "`date -u +'%F %T UTC'` (local TZ: `date +'%Z %z'`)"
   name_val "Sys Date" "`date  +'%F %T System'` (local TZ: `date +'%Z %z'`)"
   name_val "Hostname" "$(get_var hostname "${data_dir}/summary")"
   name_val "IP address" "$IP_ADDR"
   name_val "Uptime" "$(parse_uptime "${data_dir}/uptime")"

   if [ "$(get_var "vendor" "${data_dir}/summary")" ]; then
      name_val "System" "$(get_var "system" "${data_dir}/summary")";
      name_val "Service Tag" "$(get_var "servicetag" "${data_dir}/summary")";
   fi

   name_val "Platform" "${platform}"
   local zonename="$(get_var zonename "${data_dir}/summary")";
   [ -n "${zonename}" ] && name_val "Zonename" "$zonename"

   name_val "Release" "$(get_var "release" "${data_dir}/summary")"
   name_val "Kernel" "$(get_var "kernel" "${data_dir}/summary")"

   name_val "Architecture" "CPU = $(get_var "CPU_ARCH" "${data_dir}/summary"), OS = $(get_var "OS_ARCH" "${data_dir}/summary")"

   local getenforce="$(get_var getenforce "${data_dir}/summary")"
   [ -n "$getenforce" ] && name_val "SELinux" "${getenforce}";

   name_val "Virtualized" "$(get_var "virt" "${data_dir}/summary")"

   section_Processor "$platform" "${data_dir}"

   section_Memory    "$platform" "${data_dir}"
   
   if [ -s "${data_dir}/mounted_fs" ]; then
      section "Mounted Filesystems"
      parse_filesystems "${data_dir}/mounted_fs" "${platform}"
   fi

   if [ "${platform}" = "Linux" ]; then

      section "Disk Partioning"
      parse_fdisk "${data_dir}/partitioning"

      section "LVM Volumes"
      format_lvs "${data_dir}/lvs"
      section "LVM Volume Groups"
      format_lvs "${data_dir}/vgs"
      section "LVM Physical Volumes"
      format_lvs "${data_dir}/pvs"
   fi


   if [ "${OPT_SUMMARIZE_NETWORK}" ]; then
      if [ "${platform}" = "Linux" ]; then
         section "Network Models"
         if [ -s "${data_dir}/lspci_file" ]; then
            parse_ethernet_controller_lspci "${data_dir}/lspci_file"
         fi
      fi


      if [ -s "${data_dir}/ip" ]; then
         section "Interface Statistics"
         parse_ip_s_link "${data_dir}/ip"
      fi

      if [ -s "${data_dir}/network_devices" ]; then
         section "Network Devices"
         parse_ethtool "${data_dir}/network_devices"
      fi

      if [ "${platform}" = "Linux" -a -e "${data_dir}/netstat" ]; then
         section "Network Connections"
         parse_netstat "${data_dir}/netstat"
      fi
   fi

   [ "$OPT_SUMMARIZE_PROCESSES" ] && processes_section           \
                                       "${data_dir}/processes"     \
                                       "${data_dir}/notable_procs"

   custom_settings "${data_dir}"

   section "The End"
}

# ###########################################################################
# End report_system_info package
# ###########################################################################

# ###########################################################################
# ftp upload package
# This package is ftp upload functions
# ###########################################################################

ftp_upload () {
   local ftpserver=$1
   local username=$2
   local password=$3
   local outfile=$4

   /usr/bin/ftp -i -n << EOD
   open ${ftpserver}
   user ${username} ${password}
   bin
   hash
   lcd /tmp/
   passive
   mput ${outfile}
   bye
EOD
}

# ###########################################################################
# End ftp_upload package
# ###########################################################################

# ##############################################################################
# The main() function is called at the end of the script.  This makes it
# testable.  Major bits of parsing are separated into functions for testability.
# ##############################################################################
main () { local BSGFUNCNAME=main;
   trap sigtrap HUP INT TERM

   local RAN_WITH="--sleep=$OPT_SLEEP --save-samples=$OPT_SAVE_SAMPLES --read-samples=$OPT_READ_SAMPLES"

   # Begin by setting the $PATH to include some common locations that are not
   # always in the $PATH, including the "sbin" locations, and some common
   # locations for proprietary management software, such as RAID controllers.
   export PATH="${PATH}:/usr/local/bin:/usr/bin:/bin:/usr/libexec"
   export PATH="${PATH}:/usr/local/sbin:/usr/sbin:/sbin"
   export PATH="${PATH}:/usr/StorMan/:/opt/MegaRAID/MegaCli/"

   local date=${DATE}
   local hostname=$HOSTNAME
   local ipdev=${IP_DEV}
   local ip_addr=${IP_ADDR}
   local outdir="/tmp"
   local outfile="L-${hostname}-${ip_addr}-${date}.txt"
   local log_tar_file="${outdir}/L-${hostname}-${ip_addr}-${date}.messages.tar.gz"

   setup_commands

   _d "Starting $0 $RAN_WITH"

   # Set up temporary files.
   mk_tmpdir

   local data_dir="$(setup_data_dir "${OPT_SAVE_SAMPLES:-""}")"

   if [ -n "${OPT_READ_SAMPLES}" -a -d "${OPT_READ_SAMPLES}" ]; then
      data_dir="${OPT_READ_SAMPLES}"
   else
      collect_system_data "$data_dir" 2>"$data_dir/collect.err"
   fi

   report_system_summary "$data_dir" >> ${outdir}/${outfile}

   save_logs "$log_tar_file"

   rm_tmpdir
}

sigtrap() { local BSGFUNCNAME=sigtrap;
   warn "Caught signal, forcing exit"
   rm_tmpdir
   exit ${EXIT_STATUS}
}

# Execute the program if it was not included from another file.  This makes it
# possible to include without executing, and thus test.
if    [ "${0##*/}" = "$TOOL" ] \
   || [ "${0##*/}" = "bash" -a "${_:-""}" = "$0" ]; then

   # Set up temporary dir.
   mk_tmpdir
   # Parse command line options.
   parse_options "$0" "${@:-""}"
   usage_or_errors "$0"
   po_status=$?
   rm_tmpdir

   if [ ${po_status} -ne 0 ]; then
      exit ${po_status}
   fi

   main "${@:-""}"
fi

# ############################################################################
# Documentation
# ############################################################################
:<<'DOCUMENTATION'
=pod

=head1 NAME

bsg-summary - Summarize system information nicely.

=head1 SYNOPSIS

Usage: bsg-summary

bsg-summary conveniently summarizes the status and configuration of a server.
It is not a tuning tool or diagnosis tool.  It produces a report that is easy
to diff and can be pasted into emails without losing the formatting.  This
tool works well on many types of Unix systems.

Download and run:


=head1 RISKS

bsg-summary is mature, proven in the real world, and well tested,
but all database tools can pose a risk to the system and the database
server.  Before using this tool, please:

=over

=item * Read the tool's documentation

=item * Review the tool's known L<"BUGS">

=item * Test the tool on a non-production server

=item * Backup your production server and verify the backups

=back

=head1 DESCRIPTION

bsg-summary runs a large variety of commands to inspect system status and
configuration, saves the output into files in a temporary directory, and
then runs Unix commands on these results to format them nicely.  It works
best when executed as a privileged user, but will also work without privileges,
although some output might not be possible to generate without root.

=head1 OUTPUT

Many of the outputs from this tool are deliberately rounded to show their
magnitude but not the exact detail. This is called fuzzy-rounding. The idea is
that it doesn't matter whether a particular counter is 918 or 921; such a small
variation is insignificant, and only makes the output hard to compare to other
servers. Fuzzy-rounding rounds in larger increments as the input grows. It
begins by rounding to the nearest 5, then the nearest 10, nearest 25, and then
repeats by a factor of 10 larger (50, 100, 250), and so on, as the input grows.

The following is a simple report generated from a CentOS virtual machine,
broken into sections with commentary following each section. Some long lines
are reformatted for clarity when reading this documentation as a manual page in
a terminal.

 # System Summary Report ######################
         Date | 2012-03-30 00:58:07 UTC (local TZ: EDT -0400)
     Hostname | localhost.localdomain
       Uptime | 20:58:06 up 1 day, 20 min, 1 user,
                load average: 0.14, 0.18, 0.18
       System | innotek GmbH; VirtualBox; v1.2 ()
  Service Tag | 0
      Release | CentOS release 5.5 (Final)
       Kernel | 2.6.18-194.el5
 Architecture | CPU = 32-bit, OS = 32-bit
      SELinux | Enforcing
  Virtualized | VirtualBox

This section shows the current date and time, and a synopsis of the server and
operating system.

 # Processor ##################################################
   Processors | physical = 1, cores = 0, virtual = 1, hyperthreading = no
       Speeds | 1x2510.626
       Models | 1xIntel(R) Core(TM) i5-2400S CPU @ 2.50GHz
       Caches | 1x6144 KB

This section is derived from F</proc/cpuinfo>.

 # Memory #####################################################
        Total | 503.2M
         Free | 29.0M
         Used | physical = 474.2M, swap allocated = 1.0M,
                swap used = 16.0k, virtual = 474.3M
      Buffers | 33.9M
       Caches | 262.6M
        Dirty | 396 kB
  Locator  Size  Speed    Form Factor  Type    Type Detail
  =======  ====  =====    ===========  ====    ===========

Information about memory is gathered from C<free>. The Used statistic is the
total of the rss sizes displayed by C<ps>. The Dirty statistic for the cached
value comes from F</proc/meminfo>. On Linux, the swappiness settings are
gathered from C<sysctl>. The final portion of this section is a table of the
DIMMs, which comes from C<dmidecode>. In this example there is no output.

 # Mounted Filesystems ########################################
   Filesystem                       Size Used Type  Opts Mountpoint
   /dev/mapper/VolGroup00-LogVol00   15G  17% ext3  rw   /
   /dev/sda1                         99M  13% ext3  rw   /boot
   tmpfs                            252M   0% tmpfs rw   /dev/shm


 # Disk Partioning ############################################
 Device       Type      Start        End               Size
 ============ ==== ========== ========== ==================
 /dev/sda     Disk                              17179869184
 /dev/sda1    Part          1         13           98703360
 /dev/sda2    Part         14       2088        17059230720


 # LVM Volumes ################################################
 LV       VG         Attr   LSize   Origin Snap% Move Log Copy% Convert
 LogVol00 VolGroup00 -wi-ao 269.00G                                      
 LogVol01 VolGroup00 -wi-ao   9.75G   

This section shows the output of C<lvs>.


 # Network Config #############################################
   Controller | Intel Corporation 82540EM Gigabit Ethernet Controller
  FIN Timeout | 60
   Port Range | 61000

The network controllers attached to the system are detected from C<lspci>. The
TCP/IP protocol configuration parameters are extracted from C<sysctl>. You can skip this section by disabling the L<"--summarize-network"> option.

 # Interface Statistics #######################################
 interface rx_bytes rx_packets rx_errors tx_bytes tx_packets tx_errors
 ========= ======== ========== ========= ======== ========== =========
 lo        60000000      12500         0 60000000      12500         0
 eth0      15000000      80000         0  1500000      10000         0
 sit0             0          0         0        0          0         0

Interface statistics are gathered from C<ip -s link> and are fuzzy-rounded. The
columns are received and transmitted bytes, packets, and errors.  You can skip
this section by disabling the L<"--summarize-network"> option.

 # Network Connections ########################################
   Connections from remote IP addresses
     127.0.0.1           2
   Connections to local IP addresses
     127.0.0.1           2
   Connections to top 10 local ports
     38346               1
     60875               1
   States of connections
     ESTABLISHED         5
     LISTEN              8

This section shows a summary of network connections, retrieved from C<netstat>
and "fuzzy-rounded" to make them easier to compare when the numbers grow large.
There are two sub-sections showing how many connections there are per origin
and destination IP address, and a sub-section showing the count of ports in
use.  The section ends with the count of the network connections' states.  You
can skip this section by disabling the L<"--summarize-network"> option.

 # Top Processes ##############################################
   PID USER  PR  NI  VIRT  RES  SHR S %CPU %MEM    TIME+  COMMAND
     1 root  15   0  2072  628  540 S  0.0  0.1   0:02.55 init
     2 root  RT  -5     0    0    0 S  0.0  0.0   0:00.00 migration/0
     3 root  34  19     0    0    0 S  0.0  0.0   0:00.03 ksoftirqd/0
     4 root  RT  -5     0    0    0 S  0.0  0.0   0:00.00 watchdog/0
     5 root  10  -5     0    0    0 S  0.0  0.0   0:00.97 events/0
     6 root  10  -5     0    0    0 S  0.0  0.0   0:00.00 khelper
     7 root  10  -5     0    0    0 S  0.0  0.0   0:00.00 kthread
    10 root  10  -5     0    0    0 S  0.0  0.0   0:00.13 kblockd/0
    11 root  20  -5     0    0    0 S  0.0  0.0   0:00.00 kacpid
 # Notable Processes ##########################################
   PID    OOM    COMMAND
  2028    +0    sshd


=head1 OPTIONS

=over

=item --config

type: string

Read this comma-separated list of config files.  If specified, this must be the
first option on the command line.

=item --help

Print help and exit.

=item --save-samples

type: string

Save the collected data in this directory.

=item --read-samples

type: string

Create a report from the files in this directory.

=item --summarize-mounts

default: yes; negatable: yes

Report on mounted filesystems and disk usage.

=item --summarize-network

default: yes; negatable: yes

Report on network controllers and configuration.

=item --summarize-processes

default: yes; negatable: yes

Report on top processes and C<vmstat> output.

=item --sleep

type: int; default: 5

How long to sleep when gathering samples from vmstat.

=item --version

Print tool's version and exit.

=back

=head1 SYSTEM REQUIREMENTS

This tool requires the Bourne shell (F</bin/sh>).

=item * Complete command-line used to run the tool

=item * Tool L<"--version">

=item * MySQL version of all servers involved

=item * Output from the tool including STDERR

=item * Input files (log/dump/config files, etc.)

=back

If possible, include debugging output by running the tool with C<PTDEBUG>;
see L<"ENVIRONMENT">.

=head1 AUTHORS

Baron Schwartz, Kevin van Zonneveld, and Brian Fraser

=head1 VERSION

bsg-summary 2.2.1

=cut

DOCUMENTATION
