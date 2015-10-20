#!/bin/bash

##
## Collection of shell functions for Handwritten Text Recognition.
##
## @version $Revision$$Date::             $
## @author Mauricio Villegas <mauvilsa@upv.es>
## @copyright Copyright(c) 2014 to the present, Mauricio Villegas (UPV)
##

# @todo maybe shoud change @id paths to depend on base node type
# @todo or when validating check that all ids are different

[ "${BASH_SOURCE[0]}" = "$0" ] && 
  echo "htrsh.inc.sh: error: not intended for direct execution, use htrsh_load" 1>&2 &&
  exit 1;
[ "$(type -t htrsh_version)" = "function" ] &&
  echo "htrsh.inc.sh: warning: library already loaded, to reload first use htrsh_unload" 1>&2 &&
  return 0;

#-----------------------#
# Default configuration #
#-----------------------#

htrsh_keeptmp="0";

htrsh_xpath_regions='//_:TextRegion';    # XPATH for selecting Page regions to process
htrsh_xpath_lines='_:TextLine[_:Coords and _:TextEquiv/_:Unicode and _:TextEquiv/_:Unicode != ""]';
htrsh_xpath_quads='_:Coords[../_:TextLine/_:TextEquiv/_:Unicode and ../_:TextLine/_:TextEquiv/_:Unicode != ""]';
htrsh_xpath_coords='_:Coords[@points and @points!="0,0 0,0"]';

htrsh_imgtxtenh_regmask="no";                # Whether to use a region-based processing mask
htrsh_imgtxtenh_opts="-r 0.16 -w 20 -k 0.1"; # Options for imgtxtenh tool
htrsh_imglineclean_opts="-V0 -m 99%";        # Options for imglineclean tool

htrsh_feat_deslope="yes"; # Whether to correct slope per line
htrsh_feat_deslant="yes"; # Whether to correct slant of the text
htrsh_feat_padding="1.0"; # Left and right white padding in mm for line images
htrsh_feat_contour="yes"; # Whether to compute connected components contours
htrsh_feat_dilradi="0.5"; # Dilation radius in mm for contours
htrsh_feat_normxheight="18"; # Normalize x-height to a fixed number of pixels

htrsh_feat="dotmatrix";    # Type of features to extract
htrsh_dotmatrix_shift="2"; # Sliding window shift in px, should change this to mm
htrsh_dotmatrix_win="20";  # Sliding window width in px, should change this to mm
htrsh_dotmatrix_W="8";     # Width of normalized frame in px, should change this to mm
htrsh_dotmatrix_H="32";    # Height of normalized frame in px, should change this to mm
htrsh_dotmatrix_mom="yes"; # Whether to add moments to features

htrsh_align_chars="no";             # Whether to align at a character level
htrsh_align_isect="yes";            # Whether to intersect parallelograms with line contour
htrsh_align_prefer_baselines="yes"; # Whether to always generate contours from baselines
htrsh_align_addtext="yes";          # Whether to add TextEquiv to word and glyph nodes

htrsh_hmm_states="6"; # Number of HMM states (excluding special initial and final)
htrsh_hmm_nummix="4"; # Number of Gaussian mixture components per state
htrsh_hmm_iter="4";   # Number of training iterations

htrsh_HTK_HERest_opts="-m 2";      # Options for HERest tool
htrsh_HTK_HCompV_opts="-f 0.1 -m"; # Options for HCompV tool
htrsh_HTK_HHEd_opts="";            # Options for HHEd tool
htrsh_HTK_HVite_opts="";           # Options for HVite tool

htrsh_HTK_config='
HMMDEFFILTER   = "zcat $"
HMMDEFOFILTER  = "gzip > $"
HNETFILTER     = "zcat $"
HNETOFILTER    = "gzip > $"
NONUMESCAPES   = T
STARTWORD      = "<s>"
ENDWORD        = "</s>"
';

htrsh_sed_tokenize_simplest='
  s|$\.|$*|g;
  s|\([.,:;!¡?¿\x27´`"“”„(){}—–]\)| \1 |g;
  s|$\*|$.|g;
  s|\([0-9]\)| \1 |g;
  s|^  *||;
  s|  *$||;
  s|   *| |g;
  s|\. \. \.|...|g;
  ';

htrsh_sed_translit_vowels='
  s|á|a|g; s|Á|A|g;
  s|é|e|g; s|É|E|g;
  s|í|i|g; s|Í|I|g;
  s|ó|o|g; s|Ó|O|g;
  s|ú|u|g; s|Ú|U|g;
  ';

htrsh_valschema="yes";
htrsh_pagexsd="http://mvillegas.info/xsd/2013-07-15/pagecontent.xsd";
[ "$USER" = "mvillegas" ] &&
  htrsh_pagexsd="$HOME/work/prog/mvsh/HTR/xsd/pagecontent+.xsd";

htrsh_realpath="readlink -f";
[ $(realpath --help 2>&1 | grep relative | wc -l) != 0 ] &&
  htrsh_realpath="realpath --relative-to=.";


#---------------------------#
# Generic library functions #
#---------------------------#

##
## Function that prints the version of the library
##
htrsh_version () {
  echo '$Revision$$Date$' \
    | sed 's|^$Revision:|htrsh: revision|; s| (.*|)|; s|[$][$]Date: |(|;' 1>&2;
}

##
## Function that unloads the library
##
htrsh_unload () {
  unset $(compgen -A variable htrsh_);
  unset -f $(compgen -A function htrsh_);
}

##
## Function that checks that all required commands are available
##
htrsh_check_req () {
  local FN="htrsh_check_req";
  local cmd;
  for cmd in xmlstarlet convert octave HVite dotmatrix imgtxtenh imglineclean imgccomp imgpolycrop imageSlant imageSlope page_format_generate_contour; do
    local c=$(which $cmd 2>/dev/null);
    [ ! -e "$c" ] &&
      echo "$FN: WARNING: unable to find command: $cmd" 1>&2;
  done

  [ $(dotmatrix -h 2>&1 | grep '\--htk' | wc -l) = 0 ] &&
    echo "$FN: WARNING: a dotmatrix with --htk option is required" 1>&2;

  for cmd in readhtk writehtk; do
    [ $(octave -q --eval "which $cmd" | wc -l) = 0 ] &&
      echo "$FN: WARNING: unable to find octave command: $cmd" 1>&2;
  done

  htrsh_version;
  for cmd in imgtxtenh imglineclean imgpageborder imgccomp; do
    $cmd --version;
  done
  { printf "xmlstarlet "; xmlstarlet --version | head -n 1;
    convert --version | sed -n '1{ s|^Version: ||; p; }';
    octave -q --version | head -n 1;
    HVite -V | grep HVite | cat;
  } 1>&2;

  return 0;
}

##
## Function that randomly and evenly splits a list
##
htrsh_randsplit () {
  local FN="htrsh_randsplit";
  local START="0";
  if [ $# -lt 3 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Randomly and evenly splits a list";
      echo "Usage: $FN PARTS LIST OUTFORMAT [ #start (def.=$START) ]";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local PARTS="$1";
  local LIST="$2";
  local OUTFORMAT="$3";
  [ $# -gt 3 ] && START="$4";

  if [ ! -e "$LIST" ]; then
    echo "$FN: error: list not found: $LIST" 1>&2;
    return 1;
  fi

  local NLIST=$(wc -l < "$LIST");

  cat "$LIST" \
    | awk '{ printf( "%s %s\n", rand(), $0 ); }' \
    | sort \
    | sed 's|^[^ ]* ||' \
    | awk '
        BEGIN {
          fact = '$NLIST'/'$PARTS';
          part = -1;
          accu = 1;
        }
        { if( NR == 1 || nxt == NR ) {
            part += 1;
            accu += fact;
            nxt = sprintf("%.0f",accu);
            outfile = sprintf( "'"$OUTFORMAT"'", part+'"$START"' );
          }
          print > outfile;
        }
        END { printf( "%s\n", part >= 0 ? part+1 : "" ); }';
}

##
## Function that executes several instances of a command in parallel
##
htrsh_run_parallel () {
  local FN="htrsh_run_parallel";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Executes several instances of a command in parallel,";
      echo "  prepending to stderr/stdout the job identifier.";
      echo "Usage: $FN ( {id1},{id2},... | {#ini}:[{#inc}:]{#end} ) COMMAND ARG1 ARG2 ...";
      echo "Example: $ $FN A,K echo This is job JOBID";
      echo "  A:This is job A";
      echo "  K:This is job K";
    } 1>&2;
    return 1;
  fi

  local RND=$(echo "$1" | sed -n '/|/{ s/|.*//; p; }');
  local JOBS=$(echo "$1" | sed 's/^.*|//; s/,/ /g;');
  [[ "$JOBS" == *:* ]] && JOBS=$(seq ${JOBS//:/ });
  local NJOBS=$(echo $JOBS | wc -w);
  shift;

  if [ "$NJOBS" = 0 ]; then
    echo "$FN: error: unexpected job IDs" 1>&2;
    return 1;
  elif [ "$NJOBS" = 1 ]; then
    local CMD=("${@/JOBID/$JOBS}");
    "${CMD[@]}";
    return $?;
  fi

  #local TMP="${TMPDIR:-/tmp}";
  local TMP="${TMPDIR:-.}";
  if [ "$RND" = "" ]; then
    TMP=$(mktemp --tmpdir="$TMP" ${FN}_XXXXX);
  else
    TMP="$TMP/${FN}_$RND";
  fi

  local CMD=("$@");
  local n;
  for n in $(seq 0 $(($#-1))); do
    if [ -p "${CMD[n]}" ]; then
      local p=$(ls "$TMP.pipe"* 2>/dev/null | wc -l);
      cat "${CMD[n]}" > "$TMP.pipe$p";
      CMD[n]="$TMP.pipe$p";
    fi
  done
  set -- "${CMD[@]}";
  echo "$@" > "$TMP";

  ( local JOBID;
    for JOBID in ${JOBS//:/ }; do
      > "$TMP.out_$JOBID";
      > "$TMP.err_$JOBID";
    done
    local PROC_LOGS='
      ### Remove blank lines before tail file header ###
      :loop;
      /^$/ {
        N;
        /\n==> .* <==$/! { G; s|^\(.*\)\n\([^\n]*\)$|\2\1|; P; }
        D; b loop;
      }
      ### Hold job ID from tail file header ###
      /^==> .* <==$/ { s|^==> .*\.[oe][ur][tr]_\([^ ]*\) <==$|\1:|; h; d; }
      ### Prepend job ID to each line ###
      G; s|^\(.*\)\n\([^\n]*\)$|\2\1|;';
    { tail --pid=$$ -fn +1 "$TMP".out_* &
      echo "outPID $!" >> "$TMP";
    } | sed "$PROC_LOGS" &
    { tail --pid=$$ -fn +1 "$TMP".err_* &
      echo "errPID $!" >> "$TMP";
    } | sed "$PROC_LOGS" 1>&2 &

    ( for JOBID in ${JOBS//:/ }; do
        { local CMD=("${@/JOBID/$JOBID}");
          "${CMD[@]}";
          [ "$?" != 0 ] &&
            echo "JOBID:$JOBID failed" >> "$TMP";
          echo "JOBID:$JOBID ended" >> "$TMP";
        } >> "$TMP.out_$JOBID" 2>> "$TMP.err_$JOBID" &
      done
      wait;
    )
    kill $(sed -n '/^[oe][ur][tr]PID /{ s|^...PID ||; p; }' "$TMP");
  )

  NJOBS=$(grep -c '^JOBID:[^ ]* failed$' "$TMP");
  [ "$NJOBS" != 0 ] && return "$NJOBS";
  rm "$TMP"*;

  return 0;
}

##
## Function that executes instances of a command in parallel to process a list
##
# @todo create single parallel function supporting: 1) either one process per element or several, 2) elements given to command as stdin, file '{@}', '{<}' pipe, or arguments '{*}', 3) list given to parallel as argument, file or stdin, 4) threads either single number, range or mutiple names separated by commas, 4) replace in arguments '{#}' for instance number and '{%}' for thread name
htrsh_run_parallel_list () {
  local FN="htrsh_run_parallel_list";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Executes instances of a command in parallel to process a list.";
      echo "  Each thread is given part of the list, and the moment any thread finishes";
      echo "  a new instance is started with another part of the list. In the command";
      echo "  arguments, '{@}' is replaced by a file containing a partial list and '{#}'";
      echo "  by the command instance number. The thread number is prepended to every";
      echo "  line of stderr and stdout.";
      echo "Usage: $FN THREADS LIST COMMAND ARG1 ARG2 ... '{@}' ... '{#}' ...";
      #echo "Usage: $FN THREADS [OPTIONS] COMMAND ARG1 ARG2 ... ('{@}'|'{*}') ... '{#}' ... '{%}' ...";
      #echo "Options:";
      #echo " -k (yes|no)  Whether to keep temporal files (def.=$KEEPTMP)";
      #echo " -n NUMELEMS  Elements per instance, either an integer>0 or 'auto' (def.=$ELEMS)";
      #echo " -e ELEMENTS  Elements, either a file, list {id1},{id2},... or range {#ini}:[{#inc}:]{#end} (def.=from stdin)";
      echo "Environment variables:";
      echo "  TMPDIR      Directory for temporal files, must exist (def.=.)";
      echo "  TMPRND      Hash for unique temporal files (def.=mktemp command)";
      echo "Dummy example:"
      echo "  $ my_func () { sleep \$((RANDOM%3)); echo done \$1: \$(<\$2) \\(\$(wc -w < \$2) items\\); }";
      echo "  $ seq 1 100 | $FN 3 - my_func '{#}' '{@}'";
    } 1>&2;
    return 1;
  fi

  local THREADS="$1";
  local LIST="$2"; [ "$LIST" = "-" ] && LIST="/dev/stdin";
  shift 2;

  if [ ! -e "$LIST" ]; then
    echo "$FN: error: list not found: $LIST" 1>&2;
    return 1;
  elif [ "$THREADS" -le 0 ]; then
    echo "$FN: error: unexpected number of threads: $THREADS" 1>&2;
    return 1;
  fi

  LIST=$( < "$LIST" );
  local NLIST=$( echo "$LIST" | wc -l );
  [ "$NLIST" = 0 ] &&
    echo "$FN: error: list apparently empty: $LIST" 1>&2 &&
    return 1;

  local TMP="${TMPDIR:-.}";
  local RND="${TMPRND:-}";
  if [ "$RND" = "" ]; then
    TMP=$(mktemp -d --tmpdir="$TMP" ${FN}_XXXXX);
  else
    TMP="$TMP/${FN}_$RND";
    mkdir "$TMP";
  fi
  [ ! -d "$TMP" ] &&
    echo "$FN: error: failed to create temporal directory: $TMP" 1>&2 &&
    return 1;

  #if [ -p "$LIST" ] || [ "$LIST" = "/dev/stdin" ]; then
  #  cat "$LIST" > "$TMP.lst";
  #  LIST="$TMP.lst";
  #fi
  #local NLIST=$(wc -l < "$LIST");
  #[ "$NLIST" -le 0 ] &&
  #  echo "$FN: error: list apparently empty: $LIST" 1>&2 &&
  #  rmdir "$TMP" &&
  #  return 1;

  local CMD=("$@");
  local n;
  for n in $(seq 1 $(($#-1))); do
    if [ -p "${CMD[n]}" ]; then
      local p=$(ls "$TMP/pipe"* 2>/dev/null | wc -l);
      cat "${CMD[n]}" > "$TMP/pipe$p";
      CMD[n]="$TMP/pipe$p";
    fi
  done
  set -- "${CMD[@]}";
  echo "$@" > "$TMP/state";

  #awk -v fact0=0.5 -v TMP="$TMP" -v THREADS="$THREADS" -v NLIST="$NLIST" '
  #  BEGIN {
  #    fact = THREADS==1 ? 1 : fact0;
  #    limit_list = fact*NLIST/THREADS;
  #    limit_level = fact*NLIST;
  #    list = 1;
  #  }
  #  { if( NR > limit_level ) {
  #      list ++;
  #      fact *= fact0;
  #      limit_list = limit_level + fact*NLIST/THREADS;
  #      limit_level += fact*NLIST;
  #    }
  #    else if( NR > limit_list ) {
  #      list ++;
  #      limit_list += fact*NLIST/THREADS;
  #    }
  #    print >> (TMP"/list_"list);
  #  }' "$LIST";

  eval LIST=\( $( echo "$LIST" | sed 's|\x27|\\\\x27|g' | \
    awk -v fact0=0.5 -v THREADS="$THREADS" -v NLIST="$NLIST" '
      BEGIN {
        fact = THREADS==1 ? 1 : fact0;
        limit_list = fact*NLIST/THREADS;
        limit_level = fact*NLIST;
        list = 1;
        nlist = 0;
        printf( "$\x27" );
      }
      { if( NR > limit_level || NR > limit_list ) {
          list ++;
          nlist = 0;
          printf( "\x27 $\x27" );
          if( NR > limit_level ) {
            fact *= fact0;
            limit_list = limit_level + fact*NLIST/THREADS;
            limit_level += fact*NLIST;
          }
          else
            limit_list += fact*NLIST/THREADS;
        }
        printf( nlist++ > 0 ? "\\n%s" : "%s", $0 );
      }
      END { printf( "\x27" ); }' ) \);

  local TOTP=${#LIST[@]};
  #local TOTP=$(ls $TMP/list_* | wc -l);
  local JOBS=$(seq 1 $THREADS);
  [ "$THREADS" -gt "$TOTP" ] && JOBS=$(seq 1 $TOTP);

  ( local JOBID;
    for JOBID in $JOBS; do
      > "$TMP/out_$JOBID";
      > "$TMP/err_$JOBID";
    done
    local PROC_LOGS='
      ### Remove blank lines before tail file header ###
      :loop;
      /^$/ {
        N;
        /\n==> .* <==$/! { G; s|^\(.*\)\n\([^\n]*\)$|\2\1|; P; }
        D; b loop;
      }
      ### Hold job ID from tail file header ###
      /^==> .* <==$/ { s|^==> .*\.[oe][ur][tr]_\([^ ]*\) <==$|\1:|; h; d; }
      ### Prepend job ID to each line ###
      G; s|^\(.*\)\n\([^\n]*\)$|\2\1|;';

    { tail --pid=$$ -fn +1 "$TMP"/out_* &
      echo "outPID $!" >> "$TMP/state";
    } | sed "$PROC_LOGS" &
    { tail --pid=$$ -fn +1 "$TMP"/err_* &
      echo "errPID $!" >> "$TMP/state";
    } | sed "$PROC_LOGS" 1>&2 &

    ( local NUMP=0;
      for JOBID in $JOBS; do
        NUMP=$((NUMP+1));
        { local CMD=("${@/\{@\}/$TMP\/list_$NUMP}");
          local NELEM=$(echo "${LIST[$((NUMP-1))]}" | wc -l);
          echo "${LIST[$((NUMP-1))]}" > "$TMP/list_$NUMP";
          CMD=("${CMD[@]/\{\#\}/$NUMP}");
          echo "JOBID:$JOBID:$NUMP $NELEM starting" >> "$TMP/state";
          "${CMD[@]}";
          [ "$?" != 0 ] && echo "JOBID:$JOBID:$NUMP failed" >> "$TMP/state";
          echo "JOBID:$JOBID:$NUMP ended" >> "$TMP/state";
        } >> "$TMP/out_$JOBID" 2>> "$TMP/err_$JOBID" &
      done
      while true; do
        local NUMR=$(( NUMP - $(grep -c '^JOBID:[^ ]* ended$' "$TMP/state") ));
        if [ "$NUMP" = "$TOTP" ]; then
          wait;
          break;
        elif [ "$NUMR" -lt "$THREADS" ]; then
          NUMP=$((NUMP+1));
          JOBID=$(
            sed -n '/^JOBID:/{ s|^JOBID:\([^:]*\):[^ ]*|\1|; p; }' "$TMP/state" \
              | awk '
                  { if( $NF == "ended" )
                      ended[$1] = "";
                    else if( $NF == "starting" )
                      delete ended[$1];
                  } END {
                    for( job in ended ) { print job; break; }
                  }' );
          { local CMD=("${@/\{@\}/$TMP\/list_$NUMP}");
            local NELEM=$(echo "${LIST[$((NUMP-1))]}" | wc -l);
            echo "${LIST[$((NUMP-1))]}" > "$TMP/list_$NUMP";
            CMD=("${CMD[@]/\{\#\}/$NUMP}");
            echo "JOBID:$JOBID:$NUMP $NELEM starting" >> "$TMP/state";
            "${CMD[@]}";
            [ "$?" != 0 ] && echo "JOBID:$JOBID:$NUMP failed" >> "$TMP/state";
            echo "JOBID:$JOBID:$NUMP ended" >> "$TMP/state";
          } >> "$TMP/out_$JOBID" 2>> "$TMP/err_$JOBID" &
          continue;
        fi
        sleep 1;
      done
    )
    kill $(sed -n '/^[oe][ur][tr]PID /{ s|^...PID ||; p; }' "$TMP/state");
  )

  JOBS=$(grep -c '^JOBID:[^ ]* failed$' "$TMP/state");
  [ "$JOBS" != 0 ] &&
    echo $(grep '^JOBID:[^ ]* failed$' "$TMP/state") 1>&2 &&
    return "$JOBS";

  rm -r "$TMP";
  return 0;
}

#---------------------------------#
# XML Page manipulation functions #
#---------------------------------#

##
## Function that prints to stdout the TextEquiv from an XML Page file supporting several formats
##
htrsh_pagexml_textequiv () {
  local FN="htrsh_pagexml_textequiv";
  local REGSRC="no";
  local FORMAT="raw";
  local FILTER="cat";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Prints to stdout the TextEquiv from an XML Page file supporting several formats";
      echo "Usage: $FN XMLFILE [ Options ]";
      echo "Options:";
      echo " -r (yes|no)  Whether to get TextEquiv from regions instead of lines (def.=$REGSRC)";
      echo " -f FORMAT    Output format among 'raw', 'mlf-chars', 'mlf-words' and 'tab' (def.=$FORMAT)";
      echo " -F FILTER    Filtering pipe command, e.g. tokenizer, transliteration, etc. (def.=none)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  shift;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-r" ]; then
      REGSRC="$2";
    elif [ "$1" = "-f" ]; then
      FORMAT="$2";
    elif [ "$1" = "-F" ]; then
      FILTER="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check page ###
  htrsh_pageimg_info "$XML" noinfo;
  [ "$?" != 0 ] && return 1;

  local PG=$(xmlstarlet sel -t -v //@imageFilename "$XML" \
               | sed 's|.*/||; s|\.[^.]*$||; s|[\[ ()]|_|g; s|]|_|g;');

  local XPATH IDop;
  if [ "$REGSRC" = "yes" ]; then
    XPATH="$htrsh_xpath_regions/_:TextEquiv/_:Unicode[. != '']";
    IDop="-o $PG. -v ../../@id";
  else
    XPATH="$htrsh_xpath_regions/_:TextLine/_:TextEquiv/_:Unicode[. != '']";
    IDop="-o $PG. -v ../../../@id -o . -v ../../@id";
  fi

  [ $(xmlstarlet sel -t -v "count($XPATH)" "$XML") = 0 ] &&
    echo "$FN: error: zero nodes match xpath $XPATH on file: $XML" 1>&2 &&
    return 1;

  paste \
      <( xmlstarlet sel -t -m "$XPATH" $IDop -n "$XML" ) \
      <( cat "$XML" \
           | tr '\t\n' '  ' \
           | xmlstarlet sel -T -B -E utf-8 -t -m "$XPATH" -v . -n \
           | eval $FILTER ) \
    | sed '
        s|\t  *|\t|;
        s|  *$||;
        s|   *| |g;
        ' \
    | awk -F'\t' -v FORMAT=$FORMAT '
        BEGIN {
          if( FORMAT == "tab" )
            OFS=" ";
        }
        { if( FORMAT == "raw" )
            print $2;
          else if( FORMAT == "tab" )
            print $1,$2;
          else if( FORMAT == "mlf-words" ) {
            printf("\"*/%s.lab\"\n",$1);
            gsub("\x22","\\\x22",$2);
            N = split($2,txt," ");
            for( n=1; n<=N; n++ )
              printf( "\"%s\"\n", txt[n] );
            printf(".\n");
          }
          else if( FORMAT == "mlf-chars" ) {
            printf("\"*/%s.lab\"\n",$1);
            printf("@\n");
            N = split($2,txt,"");
            for( n=1; n<=N; n++ ) {
              if( txt[n] == " " )
                printf( "@\n" );
              else if( txt[n] == "@" )
                printf( "{at}\n" );
              else if( txt[n] == "_" )
                printf( "{_}\n" );
              else if( txt[n] == "\"" )
                printf( "{dquote}\n" );
              else if( txt[n] == "\x27" )
                printf( "{squote}\n" );
              else if( txt[n] == "&" )
                printf( "{amp}\n" );
              else if( txt[n] == "<" )
                printf( "{lt}\n" );
              else if( txt[n] == ">" )
                printf( "{gt}\n" );
              else if( txt[n] == "{" )
                printf( "{lbrace}\n" );
              else if( txt[n] == "}" )
                printf( "{rbrace}\n" );
              else if( match(txt[n],"[.0-9]") )
                printf( "\"%s\"\n", txt[n] );
              else
                printf("%s\n",txt[n]);
            }
            printf("@\n");
            printf(".\n");
          }
        }';

  return 0;
}

##
## Function that transforms a lab/rec MLF to kaldi table format
##
htrsh_mlf_to_tab () {
  local FN="htrsh_mlf_to_tab";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Transforms a lab/rec MLF to kaldi table format";
      echo "Usage: $FN MLF";
    } 1>&2;
    return 1;
  fi

  gawk '
    { if( $0 == "." )
        printf("\n");
      else if( $0 != "#!MLF!#" ) {
        if( NF==1 && ( match($1,/\.lab"$/) || match($1,/\.rec"$/) ) )
          printf( "%s", gensub( /^".*\/(.+)\.[lr][ae][bc]"$/, "\\1", "", $1 ) );
        else {
          if( NF > 1 )
            $1 = $3;
          if( match($1,/^".+"$/) )
            $1 = gensub( /\\"/, "\"", "g", substr($1,2,length($1)-2) );
          printf(" %s",$1);
        }
      }
    }' $1;
}

##
## Function that transforms two MLF files to the format used by tasas
##
htrsh_mlf_to_tasas () {
  local FN="htrsh_mlf_to_tasas";
  local SEPCHARS="no";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Transforms two MLF files to the format used by tasas";
      echo "Usage: $FN MLF_LAB MLF_REC [ Options ]";
      echo "Options:";
      echo " -c (yes|no)  Whether to separate characters for CER computation (def.=$SEPCHARS)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local MLF_LAB="$1";
  local MLF_REC="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-c" ]; then
      SEPCHARS="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if ! [ -e "$MLF_LAB" ]; then
    echo "$FN: error: MLF file not found: $MLF_LAB" 1>&2;
    return 1;
  elif ! [ -e "$MLF_REC" ]; then
    echo "$FN: error: MLF file not found: $MLF_REC" 1>&2;
    return 1;
  fi

  local GAWK_FORMAT_MLF='
    BEGIN {
      NMLF = 0;
      SEPCHARS = SEPCHARS == "yes" ? 1 : 0 ;
    }
    { if( match( $1, /^"\*\// ) ) {
        $1 = gensub( /^"\*\/(.+)\.[^.]+"$/, "\\1", "", $1 );
        printf( NMLF == 0 ? "%s\t" : "\n%s\t", $1 );
        NMLF ++;
        NTOKENS = 0;
      }
      else if( $0 != "#!MLF!#" && $0 != "." ) {
        if( NF >= 3 )
          $1 = $3;
        if( match( $1, /^".+"$/ ) )
          $1 = gensub( /\\"/, "\"", "g", gensub( /^"(.+)"$/, "\\1", "", $1 ) );
        if( ! SEPCHARS ) {
          printf( NTOKENS == 0 ? "%s" : " %s", $1 );
          NTOKENS ++;
        }
        else {
          if( NTOKENS > 0 )
            printf( " @" );
          N = split( $1, chars, "" );
          for( n=1; n<=N; n++ ) {
            printf( NTOKENS == 0 ? "%s" : " %s", chars[n] );
            NTOKENS ++;
          }
        }
      }
    }
    END {
      if( NMLF > 0 )
        printf( "\n" );
    }';

  awk -v SEPCHARS=$SEPCHARS "$GAWK_FORMAT_MLF" "$MLF_LAB" \
    | awk -F'\t' '
        { if( FILENAME == "-" )
            LAB[$1] = $2;
          else {
            if( !( $1 in LAB ) )
              printf( "warning: no lab for %s\n", $1 ) > "/dev/stderr";
            else
              printf( "%s|%s\n", LAB[$1], $2 );
          }
        }' - <( awk -v SEPCHARS=$SEPCHARS "$GAWK_FORMAT_MLF" "$MLF_REC" );

  return 0;
}

##
## Function that checks and extracts basic info (XMLDIR, IMDIR, IMFILE, XMLBASE, IMBASE, IMEXT, IMSIZE, IMRES, RESSRC) from an XML Page file and respective image
##
htrsh_pageimg_info () {
  local FN="htrsh_pageimg_info";
  local XML="$1";
  local VAL="-e"; [ "$htrsh_valschema" = "yes" ] && VAL="-e -s '$htrsh_pagexsd'";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Checks and extracts basic info (XMLDIR, IMDIR, IMFILE, XMLBASE, IMBASE, IMEXT, IMSIZE, IMRES, RESSRC) from an XML Page file and respective image";
      echo "Usage: $FN XMLFILE";
    } 1>&2;
    return 1;
  elif [ ! -f "$XML" ]; then
    echo "$FN: error: page file not found: $XML" 1>&2;
    return 1;
  elif [ $(eval xmlstarlet val $VAL "'$XML'" | grep ' invalid$' | wc -l) != 0 ]; then
    echo "$FN: error: invalid page file: $XML" 1>&2;
    return 1;
  fi

  if [ $# -eq 1 ] || [ "$2" != "noinfo" ]; then
    XMLDIR=$($htrsh_realpath $(dirname "$XML"));
    IMFILE="$XMLDIR/"$(xmlstarlet sel -t -v //@imageFilename "$XML");

    IMDIR=$($htrsh_realpath $(dirname "$IMFILE"));
    XMLBASE=$(echo "$XML" | sed 's|.*/||; s|\.[xX][mM][lL]$||;');
    IMBASE=$(echo "$IMFILE" | sed 's|.*/||; s|\.[^.]*$||;');
    IMEXT=$(echo "$IMFILE" | sed 's|.*\.||');

    if [ $# -eq 1 ] || [ "$2" != "noimg" ]; then
      local XMLSIZE=$(xmlstarlet sel -t -v //@imageWidth -o x -v //@imageHeight "$XML");
      IMSIZE=$(identify -format %wx%h "$IMFILE" 2>/dev/null);

      [ ! -f "$IMFILE" ] &&
        echo "$FN: error: image file not found: $IMFILE" 1>&2 &&
        return 1;
      [ "$IMSIZE" != "$XMLSIZE" ] &&
        echo "$FN: warning: image size discrepancy: image=$IMSIZE page=$XMLSIZE" 1>&2;

      RESSRC="xml";
      IMRES=$(xmlstarlet sel -t -v //_:Page/@custom "$XML" 2>/dev/null \
                | awk -F'[{}:; ]+' '
                    { for( n=1; n<=NF; n++ )
                        if( $n == "image-resolution" ) {
                          n++;
                          if( match($n,"dpcm") )
                            printf("%g",$n);
                          else if( match($n,"dpi") )
                            printf("%g",$n/2.54);
                        }
                    }');

      [ "$IMRES" = "" ] &&
      RESSRC="img" &&
      IMRES=$(
        identify -format "%x %y %U" "$IMFILE" \
          | awk '
              { if( NF == 4 ) {
                  $2 = $3;
                  $3 = $4;
                }
                if( $3 == "PixelsPerCentimeter" )
                  printf("%sx%s",$1,$2);
                else if( $3 == "PixelsPerInch" )
                  printf("%gx%g",$1/2.54,$2/2.54);
              }'
        );

      if [ "$IMRES" = "" ]; then
        echo "$FN: warning: no resolution metadata for image: $IMFILE";
      elif [ $(echo "$IMRES" | sed 's|.*x||') != $(echo "$IMRES" | sed 's|x.*||') ]; then
        echo "$FN: warning: image resolution different for vertical and horizontal: $IMFILE";
      fi 1>&2

      IMRES=$(echo "$IMRES" | sed 's|x.*||');
    fi
  fi

  return 0;
}

##
## Function that resizes an XML Page file along with its corresponding image
##
htrsh_pageimg_resize () {
  local FN="htrsh_pageimg_resize";
  local INRES="";
  local OUTRES="118";
  local INRESCHECK="yes";
  local SFACT="";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Resizes an XML Page file along with its corresponding image";
      echo "Usage: $FN XML OUTDIR [ Options ]";
      echo "Options:";
      echo " -i INRES    Input image resolution in ppc (def.=use image metadata)";
      echo " -o OUTRES   Output image resolution in ppc (def.=$OUTRES)";
      echo " -s SFACT    Scaling factor in % (def.=inferred from resolutions)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  local OUTDIR="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-i" ]; then
      INRES="$2";
    elif [ "$1" = "-o" ]; then
      OUTRES="$2";
    elif [ "$1" = "-s" ]; then
      SFACT="$2";
    elif [ "$1" = "-c" ]; then
      INRESCHECK="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check XML file and image ###
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES RESSRC;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  if [ "$INRES" = "" ] && [ "$IMRES" = "" ]; then
    echo "$FN: error: resolution not given (-i option) and image does not specify resolution: $IMFILE" 1>&2;
    return 1;
  elif [ "$INRESCHECK" = "yes" ] && [ "$INRES" = "" ] && [ $(echo $IMRES | awk '{printf("%.0f",$1)}') -lt 50 ]; then
    echo "$FN: error: image resolution ($IMRES ppc) apparently incorrect since it is unusually low to be a text document image: $IMFILE" 1>&2;
    return 1;
  elif [ ! -d "$OUTDIR" ]; then
    echo "$FN: error: output directory does not exists: $OUTDIR" 1>&2;
    return 1;
  elif [ "$XMLDIR" = $($htrsh_realpath "$OUTDIR") ]; then
    echo "$FN: error: output directory has to be different from the one containing the input XML: $XMLDIR" 1>&2;
    return 1;
  fi

  [ "$INRES" = "" ] && INRES="$IMRES";

  if [ "$SFACT" = "" ]; then
    SFACT=$(echo $OUTRES $INRES | awk '{printf("%g%%",100*$1/$2)}');
  else
    SFACT=$(echo $SFACT | sed '/%$/!s|$|%|');
    OUTRES=$(echo $SFACT $INRES | awk '{printf("%g",0.01*$1*$2)}');
  fi

  ### Resize image ###
  convert "$IMFILE" -units PixelsPerCentimeter -density $OUTRES -resize $SFACT "$OUTDIR/$IMBASE.$IMEXT"; ### don't know why the density has to be set this way

  ### Resize XML Page ###
  # @todo change the sed to XSLT
  htrsh_pagexml_resize $SFACT < "$XML" \
    | sed '
        s|\( custom="[^"]*\)image-resolution:[^;]*;\([^"]*"\)|\1\2|;
        s| custom=" *"||;
        ' \
    > "$OUTDIR/$XMLBASE.xml";

  return 0;
}

##
## Function that reorders lines of an XML Page file based ONLY on the baseline's first x,y coordinates
##
htrsh_pagexml_orderlines () {
  local FN="htrsh_pagexml_orderlines";
  if [ $# != 0 ]; then
    { echo "$FN: Error: Incorrect input arguments";
      echo "Description: Reorders the lines of an XML Page file based ONLY on the baseline's first x,y coordinates";
      echo "Usage: $FN < XML_PAGE_FILE";
    } 1>&2;
    return 1;
  fi

  local XSLT='<?xml version="1.0"?>
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  xmlns:_="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  version="1.0">

  <xsl:output method="xml" indent="yes" encoding="utf-8" omit-xml-declaration="no"/>

  <xsl:variable name="Width" select="//_:Page/@imageWidth"/>

  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//_:TextRegion[count(_:TextLine)=count(_:TextLine/_:Baseline)]">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()[not(self::_:TextLine)]" />
      <xsl:apply-templates select="_:TextLine">
        <!--<xsl:sort select="number(substring-before(substring-after(_:Baseline/@points,&quot;,&quot;),&quot; &quot;))" data-type="number" order="ascending"/>-->
        <xsl:sort select="number(substring-before(substring-after(_:Baseline/@points,&quot;,&quot;),&quot; &quot;))+(number(substring-before(_:Baseline/@points,&quot;,&quot;)) div number($Width))" data-type="number" order="ascending"/>
      </xsl:apply-templates>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>';

  xmlstarlet tr <( echo "$XSLT" ) < /dev/stdin;

  return $?;
}

##
## Function that resizes an XML Page file
##
htrsh_pagexml_resize () {
  local FN="htrsh_pagexml_resize";
  local newWidth newHeight scaleFact;
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Resizes an XML Page file";
      echo "Usage: $FN ( {newWidth}x{newHeight} | {scaleFact}% ) < XML_PAGE_FILE";
    } 1>&2;
    return 1;
  elif [ $(echo "$1" | grep -P '^[0-9]+x[0-9]+$' | wc -l) = 1 ]; then
    newWidth=$(echo "$1" | sed 's|x.*||');
    newHeight=$(echo "$1" | sed 's|.*x||');
  elif [ $(echo "$1" | grep -P '^[0-9.]+%$' | wc -l) = 1 ]; then
    scaleFact=$(echo "$1" | sed 's|%$||');
  fi

  local XSLT='<?xml version="1.0"?>
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:str="http://exslt.org/strings"
  xmlns="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  xmlns:_="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  extension-element-prefixes="str"
  version="1.0">

  <xsl:output method="xml" indent="yes" encoding="utf-8" omit-xml-declaration="no"/>

  <xsl:variable name="oldWidth" select="//_:Page/@imageWidth"/>
  <xsl:variable name="oldHeight" select="//_:Page/@imageHeight"/>';

  if [ "$scaleFact" != "" ]; then
    XSLT="$XSLT"'
  <xsl:variable name="scaleWidth" select="number('${scaleFact}') div 100"/>
  <xsl:variable name="scaleHeight" select="$scaleWidth"/>
  <xsl:variable name="newWidth" select="round($oldWidth*$scaleWidth)"/>
  <xsl:variable name="newHeight" select="round($oldHeight*$scaleHeight)"/>';
  else
    XSLT="$XSLT"'
  <xsl:variable name="newWidth" select="'${newWidth}'"/>
  <xsl:variable name="newHeight" select="'${newHeight}'"/>
  <xsl:variable name="scaleWidth" select="number($newWidth) div number($oldWidth)"/>
  <xsl:variable name="scaleHeight" select="number($newHeight) div number($oldHeight)"/>';
  fi

  XSLT="$XSLT"'
  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//_:Page">
    <xsl:copy>
      <xsl:attribute name="imageWidth">
        <xsl:value-of select="$newWidth"/>
      </xsl:attribute>
      <xsl:attribute name="imageHeight">
        <xsl:value-of select="$newHeight"/>
      </xsl:attribute>
      <xsl:apply-templates select="@*[local-name() != '"'imageWidth'"' and local-name() != '"'imageHeight'"'] | node()" />
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//*[@points]">
    <xsl:copy>
      <xsl:for-each select="@*[local-name() = '"'points'"' or local-name() = '"'fpgram'"']">
      <xsl:attribute name="{local-name()}">
        <xsl:for-each select="str:tokenize(.,'"', '"')">
          <xsl:choose>
            <xsl:when test="position() = 1">
              <xsl:value-of select="number($scaleWidth)*number(.)"/>
              <!--<xsl:value-of select="round(number($scaleWidth)*number(.))"/>-->
            </xsl:when>
            <xsl:when test="position() mod 2 = 0">
              <xsl:text>,</xsl:text><xsl:value-of select="number($scaleHeight)*number(.)"/>
              <!--<xsl:text>,</xsl:text><xsl:value-of select="round(number($scaleHeight)*number(.))"/>-->
            </xsl:when>
            <xsl:otherwise>
              <xsl:text> </xsl:text><xsl:value-of select="number($scaleWidth)*number(.)"/>
              <!--<xsl:text> </xsl:text><xsl:value-of select="round(number($scaleWidth)*number(.))"/>-->
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each>
      </xsl:attribute>
      </xsl:for-each>
      <xsl:apply-templates select="@*[local-name() != '"'points'"' and local-name() != '"'fpgram'"'] | node()" />
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>';

  xmlstarlet tr <( echo "$XSLT" ) < /dev/stdin;

  return $?;
}

##
## Function that rounds coordinate values in an XML Page file
##
htrsh_pagexml_round () {
  local FN="htrsh_pagexml_round";
  if [ $# != 0 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Resizes an XML Page file";
      echo "Usage: $FN < XML_PAGE_FILE";
    } 1>&2;
    return 1;
  fi

  local XSLT='<?xml version="1.0"?>
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:str="http://exslt.org/strings"
  xmlns="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  xmlns:_="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  extension-element-prefixes="str"
  version="1.0">

  <xsl:output method="xml" indent="yes" encoding="utf-8" omit-xml-declaration="no"/>

  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//*[@points]">
    <xsl:copy>
      <xsl:for-each select="@*[local-name() = '"'points'"' or local-name() = '"'fpgram'"']">
        <xsl:attribute name="{local-name()}">
        <xsl:for-each select="str:tokenize(.,'"', '"')">
          <xsl:choose>
            <xsl:when test="position() mod 2 = 0">
              <xsl:text>,</xsl:text>
            </xsl:when>
            <xsl:when test="position() != 1">
              <xsl:text> </xsl:text>
            </xsl:when>
          </xsl:choose>
          <xsl:value-of select="round(number(.))"/>
        </xsl:for-each>
        </xsl:attribute>
      </xsl:for-each>
      <xsl:apply-templates select="@*[local-name() != '"'points'"' and local-name() != '"'fpgram'"'] | node()" />
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>';

  xmlstarlet tr <( echo "$XSLT" ) < /dev/stdin;

  return $?;
}

##
## Function that sorts TextLines within each TextRegion in an XML Page file
## (sorts using only the first Y coordinate of baselines)
##
htrsh_pagexml_sort_lines () {
  local FN="htrsh_pagexml_sort_lines";
  if [ $# != 0 ]; then
    { echo "$FN: error: function does not expect arguments";
      echo "Description: Sorts TextLines within each TextRegion in an XML Page file (sorts using only the first Y coordinate of baselines)";
      echo "Usage: $FN < XMLIN";
    } 1>&2;
    return 1;
  fi

  local XSLT='<?xml version="1.0"?>
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  xmlns:_="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  version="1.0">

  <xsl:output method="xml" indent="yes" encoding="utf-8" omit-xml-declaration="no"/>

  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//_:TextRegion">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()[not(self::_:TextLine)]" />
      <xsl:apply-templates select="_:TextLine">
        <xsl:sort select="number(substring-before(substring-after(_:Baseline/@points,&quot;,&quot;),&quot; &quot;))" data-type="number" order="ascending"/>
      </xsl:apply-templates>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>';

  xmlstarlet tr <( echo "$XSLT" ) < /dev/stdin;

  return $?;
}

##
## Function that sorts TextRegions in an XML Page file
## (sorts using only the minimum Y coordinate of the region Coords)
##
htrsh_pagexml_sort_regions () {
  local FN="htrsh_pagexml_sort_regions";
  if [ $# != 0 ]; then
    { echo "$FN: error: function does not expect arguments";
      echo "Description: Sorts TextRegions in an XML Page file (sorts using only the minimum Y coordinate of the region Coords)";
      echo "Usage: $FN < XMLIN";
    } 1>&2;
    return 1;
  fi

  local XSLT='<?xml version="1.0"?>
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  xmlns:_="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  version="2.0">

  <xsl:output method="xml" indent="yes" encoding="utf-8" omit-xml-declaration="no"/>

  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//_:Page">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()[not(self::_:TextRegion)]" />
      <xsl:apply-templates select="_:TextRegion">
        <xsl:sort select="min(for $i in tokenize(replace(_:Coords/@points,'"'\d+,'"','"''"'),'"' '"') return number($i))" data-type="number" order="ascending"/>
      </xsl:apply-templates>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>';

  saxonb-xslt -s:- -xsl:<( echo "$XSLT" ) < /dev/stdin;

  return $?;
}

##
## Function that relabels ids of TextRegions and TextLines in an XML Page file
##
htrsh_pagexml_relabel () {
  local FN="htrsh_pagexml_relabel";
  if [ $# != 0 ]; then
    { echo "$FN: error: function does not expect arguments";
      echo "Description: Relabels ids of TextRegions and TextLines in an XML Page file";
      echo "Usage: $FN < XMLIN";
    } 1>&2;
    return 1;
  fi

  local XSLT1='<?xml version="1.0"?>
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  xmlns:_="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  version="1.0">

  <xsl:output method="xml" indent="yes" encoding="utf-8" omit-xml-declaration="no"/>

  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//_:TextRegion">
    <xsl:copy>
      <xsl:attribute name="id">
        <xsl:value-of select="'"'t'"'"/>
        <xsl:number count="//_:TextRegion"/>
      </xsl:attribute>
      <xsl:apply-templates select="@*[local-name() != '"'id'"'] | node()" />
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>';

  local XSLT2='<?xml version="1.0"?>
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  xmlns:_="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
  version="1.0">

  <xsl:output method="xml" indent="yes" encoding="utf-8" omit-xml-declaration="no"/>

  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//_:TextRegion/_:TextLine">
    <xsl:variable name="pid" select="../@id"/>
    <xsl:copy>
      <xsl:attribute name="id">
        <xsl:value-of select="concat(../@id,&quot;_l&quot;)"/>
        <xsl:number count="//_:TextRegion/_:TextLine"/>
      </xsl:attribute>
      <xsl:apply-templates select="@*[local-name() != '"'id'"'] | node()" />
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>';

  xmlstarlet tr <( echo "$XSLT1" ) < /dev/stdin \
    | xmlstarlet tr <( echo "$XSLT2" );

  return $?;
}

##
## Function that replaces @points with the respective @fpgram in an XML Page file
##
htrsh_pagexml_fpgram2points () {
  local FN="htrsh_pagexml_fpgram2points";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Replaces @points with the respective @fpgram in an XML Page file";
      echo "Usage: $FN XML";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";

  local cmd="xmlstarlet ed";
  local id;
  for id in $(xmlstarlet sel -t -m '//_:TextLine/_:Coords[@fpgram]' -v ../@id -n "$XML"); do
    cmd="$cmd -d '//_:TextLine[@id=\"$id\"]/_:Coords/@points'";
    cmd="$cmd -r '//_:TextLine[@id=\"$id\"]/_:Coords/@fpgram' -v points";
  done

  eval $cmd "'$XML'";

  return 0;
}


#--------------------------------------#
# Feature extraction related functions #
#--------------------------------------#

##
## Function that cleans and enhances a text image based on regions defined in an XML Page file
##
htrsh_pageimg_clean () {
  local FN="htrsh_pageimg_clean";
  local INRES="";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Cleans and enhances a text image based on regions defined in an XML Page file";
      echo "Usage: $FN XML OUTDIR [ Options ]";
      echo "Options:";
      echo " -i INRES    Input image resolution in ppc (def.=use image metadata)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  local OUTDIR="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-i" ]; then
      INRES="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check XML file and image ###
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES RESSRC;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  if [ ! -d "$OUTDIR" ]; then
    echo "$FN: error: output directory does not exists: $OUTDIR" 1>&2;
    return 1;
  elif [ "$INRES" = "" ] && [ $(echo $IMRES | awk '{printf("%.0f",$1)}') -lt 50 ]; then
    echo "$FN: error: image resolution ($IMRES ppc) apparently incorrect since it is unusually low to be a text document image: $IMFILE" 1>&2;
    return 1;
  elif [ "$XMLDIR" = $($htrsh_realpath "$OUTDIR") ]; then
    echo "$FN: error: output directory has to be different from the one containing the input XML: $XMLDIR" 1>&2;
    return 1;
  fi

  [ "$INRES" = "" ] && [ "$IMRES" != "" ] && INRES=$IMRES;
  [ "$INRES" != "" ] && INRES="-d $INRES";

  ### Enhance image ###
  if [ "$htrsh_imgtxtenh_regmask" != "yes" ]; then
    imgtxtenh $htrsh_imgtxtenh_opts $INRES "$IMFILE" "$OUTDIR/$IMBASE.png" 2>&1;

  else
    local IXPATH="";
    [ $(echo "$htrsh_xpath_regions" | grep -F '[' | wc -l) = 1 ] &&
      IXPATH=$(echo "$XPATH" | sed 's|\[\([^[]*\)]|[not(\1)]|');

    local textreg=$(xmlstarlet sel -t -m "$htrsh_xpath_regions/_:Coords" -v @points -n \
                      "$XML" 2>/dev/null \
                      | awk '{printf(" -draw \"polygon %s\"",$0)}');
    local othreg="";
    [ "$IXPATH" != "" ] &&
      othreg=$(xmlstarlet sel -t -m "$IXPATH/_:Coords" -v @points -n \
                     "$XML" 2>/dev/null \
                     | awk '{printf(" -draw \"polygon %s\"",$0)}');

    ### Create mask and enhance selected text regions ###
    eval convert -size $IMSIZE xc:black \
        -fill white -stroke white $textreg \
        -fill black -stroke black $othreg \
        -alpha copy "'$IMFILE'" +swap \
        -compose copy-opacity -composite miff:- \
      | imgtxtenh $htrsh_imgtxtenh_opts $INRES - "$OUTDIR/$IMBASE.png" 2>&1;
  fi

  [ "$?" != 0 ] &&
    echo "$FN: error: problems enhancing image: $IMFILE" 1>&2 &&
    return 1;

  ### Create new XML with image in current directory and PNG extension ###
  xmlstarlet ed -P -u //@imageFilename -v "$IMBASE.png" "$XML" \
    > "$OUTDIR/$XMLBASE.xml";

  return 0;
}

##
## Function that removes noise from borders of a quadrilateral region defined in an XML Page file
##
htrsh_pageimg_quadborderclean () {
  local FN="htrsh_pageimg_quadborderclean";
  local TMPDIR=".";
  local CFG="";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Removes noise from borders of a quadrilateral region defined in an XML Page file";
      echo "Usage: $FN XML OUTIMG [ Options ]";
      echo "Options:";
      echo " -c CFG      Options for imgpageborder (def.=$CFG)";
      echo " -d TMPDIR   Directory for temporary files (def.=$TMPDIR)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  local OUTIMG="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-c" ]; then
      CFG="$2";
    elif [ "$1" = "-d" ]; then
      TMPDIR="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check XML file and image ###
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES RESSRC;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  local IMW=$(echo "$IMSIZE" | sed 's|x.*||');
  local IMH=$(echo "$IMSIZE" | sed 's|.*x||');

  ### Get quadrilaterals ###
  local QUADs=$(xmlstarlet sel -t -m "$htrsh_xpath_regions/$htrsh_xpath_quads" -v @points -n "$XML");
  local N=$(echo "$QUADs" | wc -l);

  local comps="";
  local n;
  for n in $(seq 1 $N); do
    local quad=$(echo "$QUADs" | sed -n ${n}p);
    [ $(echo "$quad" | wc -w) != 4 ] &&
      echo "$FN: error: region not a quadrilateral: $XML" 1>&2 &&
      return 1;

    local persp1=$(
      echo "$quad" \
        | awk -F'[ ,]' -v imW=$IMW -v imH=$IMH '
            { w = $3-$1;
              if( w > $5-$7 )
                w = $5-$7;
              h = $6-$4;
              if( h > $8-$2 )
                h = $8-$2;

              printf("-distort Perspective \"");
              printf("%d,%d %d,%d  ",$1,$2,0,0);
              printf("%d,%d %d,%d  ",$3,$4,w-1,0);
              printf("%d,%d %d,%d  ",$5,$6,w-1,h-1);
              printf("%d,%d %d,%d"  ,$7,$8,0,h-1);
              printf("\" -crop %dx%d+0+0\n",w,h);

              printf("-extent %dx%d+0+0 ",imW,imH);
              printf("-distort Perspective \"");
              printf("%d,%d %d,%d  ",0,0,$1,$2);
              printf("%d,%d %d,%d  ",w-1,0,$3,$4);
              printf("%d,%d %d,%d  ",w-1,h-1,$5,$6);
              printf("%d,%d %d,%d"  ,0,h-1,$7,$8);
              printf("\"\n");
            }');

    local persp0=$(echo "$persp1" | sed -n 1p);
    persp1=$(echo "$persp1" | sed -n 2p);

    eval convert "$IMFILE" $persp0 "$TMPDIR/${IMBASE}~${n}-persp.$IMEXT";

    imgpageborder $CFG -M "$TMPDIR/${IMBASE}~${n}-persp.$IMEXT" "$TMPDIR/${IMBASE}~${n}-pborder.$IMEXT";
    [ $? != 0 ] &&
      echo "$FN: error: problems estimating border: $XML" 1>&2 &&
      return 1;

    #eval convert -virtual-pixel white -background white "$TMPDIR/${IMBASE}~${n}-pborder.$IMEXT" $persp1 -white-threshold 1% "$TMPDIR/${IMBASE}~${n}-border.$IMEXT";
    eval convert -virtual-pixel black -background black "$TMPDIR/${IMBASE}~${n}-pborder.$IMEXT" $persp1 -white-threshold 1% -stroke white -strokewidth 3 -fill none -draw \"polygon $quad $(echo $quad | sed 's| .*||')\" "$TMPDIR/${IMBASE}~${n}-border.$IMEXT";
    #eval convert -virtual-pixel black -background black "$TMPDIR/${IMBASE}~${n}-pborder.$IMEXT" $persp1 -white-threshold 1% "$TMPDIR/${IMBASE}~${n}-border.$IMEXT";

    comps="$comps $TMPDIR/${IMBASE}~${n}-border.$IMEXT -composite";

    if [ "$htrsh_keeptmp" -lt 2 ]; then
      rm "$TMPDIR/${IMBASE}~${n}-persp.$IMEXT" "$TMPDIR/${IMBASE}~${n}-pborder.$IMEXT";
    fi
  done

  eval convert -compose lighten "$IMFILE" $comps "$OUTIMG";

  if [ "$htrsh_keeptmp" -lt 1 ]; then
    rm "$TMPDIR/${IMBASE}~"*"-border.$IMEXT";
  fi
  return 0;
}

##
## Function that extracts lines from an image given its XML Page file
##
htrsh_pageimg_extract_lines () {
  local FN="htrsh_pageimg_extract_lines";
  local OUTDIR=".";
  local IMFILE="";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Extracts lines from an image given its XML Page file";
      echo "Usage: $FN XMLFILE [ Options ]";
      echo "Options:";
      echo " -d OUTDIR   Output directory for images (def.=$OUTDIR)";
      echo " -i IMFILE   Extract from provided image (def.=@imageFilename in XML)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  shift;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      OUTDIR="$2";
    elif [ "$1" = "-i" ]; then
      IMFILE="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check page and obtain basic info ###
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES RESSRC;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  local NUMLINES=$(xmlstarlet sel -t -v "count($htrsh_xpath_regions/$htrsh_xpath_lines/$htrsh_xpath_coords)" "$XML");

  if [ "$NUMLINES" = 0 ]; then
    echo "$FN: error: zero lines have coordinates for extraction: $XML" 1>&2;
    return 1;

  else
    local base=$(echo "$OUTDIR/$IMBASE" | sed 's|[\[ ()]|_|g; s|]|_|g;');

    if [ "$RESSRC" = "xml" ]; then
      IMRES="-d $IMRES";
    else
      IMRES="";
    fi

    xmlstarlet sel -t -m "$htrsh_xpath_regions/$htrsh_xpath_lines/_:Coords" \
        -o "$base." -v ../../@id -o "." -v ../@id -o ".png " -v @points -n "$XML" \
      | imgpolycrop $IMRES "$IMFILE";

    [ "$?" != 0 ] &&
      echo "$FN: error: line image extraction failed" 1>&2 &&
      return 1;
  fi

  return 0;
}

##
## Function that discretizes a list of features using a given codebook
##
htrsh_feats_discretize () {
  local FN="htrsh_feats_discretize";
  if [ $# -lt 3 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Discretizes a list of features using a given codebook";
      echo "Usage: $FN FEATLST CBOOK OUTDIR";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local FEATLST="$1";
  local CBOOK="$2";
  local OUTDIR="$3";

  if [ ! -e "$FEATLST" ]; then
    echo "$FN: error: features list file does not exists: $FEATLST" 1>&2;
    return 1;
  elif [ ! -e "$CBOOK" ]; then
    echo "$FN: error: codebook file does not exists: $CBOOK" 1>&2;
    return 1;
  elif [ ! -d "$OUTDIR" ]; then
    echo "$FN: error: output directory does not exists: $OUTDIR" 1>&2;
    return 1;
  fi

  local CFG="$htrsh_HTK_config"'
TARGETKIND     = USER_V
VQTABLE        = '"$CBOOK"'
SAVEASVQ       = T
';

  local LST=$(sed 's|\(.*/\)\(.*\)|\1\2 '"$OUTDIR"'/\2|; t; s|\(.*\)|\1 '"$OUTDIR"'/\1|;' "$FEATLST");

  HCopy -C <( echo "$CFG" ) $LST;
  [ "$?" != 0 ] &&
    echo "$FN: error: problems discretizing features" 1>&2 &&
    return 1;

  return 0;
}

##
## Function that extracts features from an image
##
htrsh_extract_feats () {
  local FN="htrsh_extract_feats";
  local XHEIGHT="";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Extracts features from an image";
      echo "Usage: $FN IMGIN FEAOUT [ Options ]";
      echo "Options:";
      echo " -xh XHEIGHT  The image x-height for size normalization";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local IMGIN="$1";
  local FEAOUT="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-xh" ]; then
      XHEIGHT="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  local IMGPROC="$IMGIN";
  if [ "$XHEIGHT" != "" ] && [ "$htrsh_feat_normxheight" != "" ]; then
    IMGPROC=$(mktemp).png;
    convert "$IMGIN" -resize $(echo "100*$htrsh_feat_normxheight/$XHEIGHT" | bc -l)% "$IMGPROC";
  fi

  ### Extract features ###
  if [ "$htrsh_feat" = "dotmatrix" ]; then
    local featcfg="-S --htk --width $htrsh_dotmatrix_W --height $htrsh_dotmatrix_H --shift=$htrsh_dotmatrix_shift --win-size=$htrsh_dotmatrix_win -i";
    if [ "$htrsh_dotmatrix_mom" = "yes" ]; then
      dotmatrix -m $featcfg "$IMGPROC";
    else
      dotmatrix $featcfg "$IMGPROC";
    fi > "$FEAOUT";

  elif [ "$htrsh_feat" = "prhlt" ]; then
    local TMP=$(mktemp);
    convert "$IMGPROC" $TMP.pgm;
    pgmtextfea -F 2.5 -i $TMP.pgm > $TMP.fea;
    pfl2htk $TMP.fea "$FEAOUT" 2>/dev/null;
    rm $TMP $TMP.{pgm,fea};

  elif [ "$htrsh_feat" = "fki" ]; then
    local TMP=$(mktemp);
    convert "$IMGPROC" -threshold 50% $TMP.pbm;
    fkifeat $TMP.pbm > $TMP.fea;
    pfl2htk $TMP.fea "$FEAOUT" 2>/dev/null;
    rm $TMP $TMP.{pbm,fea};

  else
    echo "$FN: error: unknown features type: $htrsh_feat" 1>&2;
    return 1;
  fi

  [ "$IMGIN" != "$IMGPROC" ] && [ "$htrsh_keeptmp" = 0 ] &&
    rm "$IMGPROC" "${IMGPROC%.png}";

  return 0;
}

##
## Function that concatenates line features for regions defined in an XML Page file
##
htrsh_feats_catregions () {
  local FN="htrsh_feats_catregions";
  local FEATLST="/dev/stdout";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Concatenates line features for regions defined in an XML Page file";
      echo "Usage: $FN XML FEATDIR [ Options ]";
      echo "Options:";
      echo " -l FEATLST  Output list of features to file (def.=$FEATLST)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  local FEATDIR="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-l" ]; then
      FEATLST="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check page and obtain basic info ###
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES RESSRC;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  [ ! -e "$FEATDIR" ] &&
    echo "$FN: error: features directory not found: $FEATDIR" 1>&2 &&
    return 1;

  local FBASE=$(echo "$FEATDIR/$IMBASE" | sed 's|[\[ ()]|_|g; s|]|_|g;');

  xmlstarlet sel -t -m "$htrsh_xpath_regions/_:TextLine/_:Coords" \
      -o "$FBASE." -v ../../@id -o "." -v ../@id -o ".fea" -n "$XML" \
    | xargs ls >/dev/null;
  [ "$?" != 0 ] &&
    echo "$FN: error: some line features files not found" 1>&2 &&
    return 1;

  local id;
  for id in $(xmlstarlet sel -t -m "$htrsh_xpath_regions[_:TextLine/_:Coords]" -v @id -n "$XML"); do
    local ff="";
    local f;
    for f in $(xmlstarlet sel -t -m "//*[@id=\"$id\"]/_:TextLine[_:Coords]" -o "$FBASE.$id." -v @id -o ".fea" -n "$XML"); do
      if [ "$ff" = "" ]; then
        ff="'$f'";
      else
        ff="$ff + '$f'";
      fi
    done
    eval HCopy $ff "'$FBASE.$id.fea'";

    echo "$FBASE.$id.fea" >> "$FEATLST";
  done

  return 0;
}

##
## Function that computes a PCA base for a given list of HTK features
##
htrsh_feats_pca () {
  local FN="htrsh_feats_pca";
  local EXCL="[]";
  local RDIM="";
  local RNDR="no";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Computes a PCA base for a given list of HTK features";
      echo "Usage: $FN FEATLST OUTMAT [ Options ]";
      echo "Options:";
      echo " -e EXCL     Dimensions to exclude in matlab range format (def.=false)";
      echo " -r RDIM     Return base of RDIM dimensions (def.=all)";
      echo " -R (yes|no) Random rotation (def.=$RNDR)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local FEATLST="$1";
  local OUTMAT="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-e" ]; then
      EXCL="$2";
    elif [ "$1" = "-r" ]; then
      RDIM="$2";
    elif [ "$1" = "-R" ]; then
      RNDR="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if [ ! -e "$FEATLST" ]; then
    echo "$FN: error: feature list not found: $FEATLST" 1>&2;
    return 1;
  elif [ $(wc -l < "$FEATLST") != $(xargs ls < "$FEATLST" | wc -l) ]; then
    echo "$FN: error: some files in list not found: $FEATLST" 1>&2;
    return 1;
  fi

  local htrsh_fastpca="no";
  if [ "$htrsh_fastpca" = "yes" ]; then

    local DIMS=$(HList -h -z $(head -n 1 < "$FEATLST") \
            | sed -n '/^  Num Comps:/{s|^[^:]*: *||;s| .*||;p;}');
    tail -qc +13 $(< "$FEATLST") | swap4bytes | fast_pca -C -e $EXCL -f binary -b 500 -p $DIMS -m "$OUTMAT";

  else

  local xEXCL=""; [ "$EXCL" != "[]" ] && xEXCL="se = se + sum(x(:,$EXCL)); x(:,$EXCL) = [];";
  local nRDIM="D"; [ "$RDIM" != "" ] && nRDIM="min(D,$RDIM)";

  { local f=$(head -n 1 < "$FEATLST");
    echo "
      DE = length($EXCL);
      se = zeros(1,DE);
      x = readhtk('$f'); $xEXCL
      N = size(x,1);
      mu = sum(x);
      sgma = x'*x;
    ";
    for f in $(tail -n +2 < "$FEATLST"); do
      echo "
        x = readhtk('$f'); $xEXCL
        N = N + size(x,1);
        mu = mu + sum(x);
        sgma = sgma + x'*x;
      ";
    done
    echo "
      mu = (1/N)*mu;
      sgma = (1/N)*sgma - mu'*mu;
      sgma = 0.5*(sgma+sgma');
      [ B, V ] = eig(sgma);
      V = real(diag(V));
      [ srt, idx ] = sort(-1*V);
      V = V(idx);
      B = B(:,idx);
      D = size(sgma,1);
      DR = $nRDIM-DE;
      B = B(:,1:DR);
    ";
    if [ "$EXCL" != "[]" ]; then
      echo "
        sel = true(DE+D,1);
        sel($EXCL) = false;
        selc = [ false(DE,1) ; true(DR,1) ];
        BB = zeros(DE+D,DE+DR);
        BB(sel,selc) = B;
        BB(~sel,~selc) = eye(DE);
        B = BB;
        mmu = zeros(1,DE+D);
        mmu(sel) = mu;
        mmu(~sel) = (1/N)*se;
        mu = mmu;
      ";
    fi
    if [ "$RNDR" = "yes" ]; then
      echo "
        rand('state',1);
        [ R, ~ ] = qr(rand(size(B,2)));
        B = B*R;
      ";
    fi
    echo "save('-z','$OUTMAT','B','V','mu');";
  } | octave -q -H;

  fi

  [ "$?" != 0 ] &&
    echo "$FN: error: problems computing PCA" 1>&2 &&
    return 1;

  return 0;
}

##
## Function that projects a list of features for a given base
##
htrsh_feats_project () {
  local FN="htrsh_feats_project";
  if [ $# -lt 3 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Projects a list of features for a given base";
      echo "Usage: $FN FEATLST PBASE OUTDIR";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local FEATLST="$1";
  local PBASE="$2";
  local OUTDIR="$3";

  if [ ! -e "$FEATLST" ]; then
    echo "$FN: error: features list file does not exists: $FEATLST" 1>&2;
    return 1;
  elif [ ! -e "$PBASE" ]; then
    echo "$FN: error: projection base does not exists: $PBASE" 1>&2;
    return 1;
  elif [ ! -d "$OUTDIR" ]; then
    echo "$FN: error: output directory does not exists: $OUTDIR" 1>&2;
    return 1;
  fi

  { echo "load('$PBASE');"
    local f ff;
    for f in $(< "$FEATLST"); do
      ff=$(echo "$f" | sed "s|.*/|$OUTDIR/|");
      echo "
        [x,FP,DT,TC,T] = readhtk('$f');
        x = (x-repmat(mu,size(x,1),1))*B;
        writehtk('$ff',x,FP,TC);
        ";
    done
  } | octave -q -H;

  [ "$?" != 0 ] &&
    echo "$FN: error: problems projecting features" 1>&2 &&
    return 1;

  return 0;
}

##
## Function that converts a list of features in HTK format to Kaldi ark,scp
##
htrsh_feats_htk_to_kaldi () {
  local FN="htrsh_feats_htk_to_kaldi";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Converts a list of features in HTK format to Kaldi ark,scp";
      echo "Usage: $FN OUTBASE < FEATLST";
    } 1>&2;
    return 1;
  fi

  cat /dev/stdin \
    | sed '
        s|^\([^/]*\)\.fea$|\1 \1.fea|;
        s|^\(.*/\)\([^/]*\)\.fea$|\2 \1\2.fea|;
        ' \
    | copy-feats --htk-in scp:- ark,scp:$1.ark,$1.scp;

  return $?;
}

##
## Function that extracts line features from an image given its XML Page file
##
htrsh_pageimg_extract_linefeats () {
  local FN="htrsh_pageimg_extract_linefeats";
  local OUTDIR=".";
  local FEATLST="$OUTDIR/feats.lst";
  local PBASE="";
  local REPLC="yes";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Extracts line features from an image given its XML Page file";
      echo "Usage: $FN XMLIN XMLOUT [ Options ]";
      echo "Options:";
      echo " -d OUTDIR   Output directory for features (def.=$OUTDIR)";
      echo " -l FEATLST  Output list of features to file (def.=$FEATLST)";
      echo " -b PBASE    Project features using given base (def.=false)";
      echo " -c (yes|no) Whether to replace Coords/@points with the features contour (def.=$REPLC)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  local XMLOUT="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      OUTDIR="$2";
    elif [ "$1" = "-l" ]; then
      FEATLST="$2";
    elif [ "$1" = "-b" ]; then
      PBASE="-b $2";
    elif [ "$1" = "-c" ]; then
      REPLC="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check page and obtain basic info ###
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES RESSRC;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  ### Extract lines from line coordinates ###
  local LINEIMGS=$(htrsh_pageimg_extract_lines "$XML" -d "$OUTDIR");
  ( [ "$?" != 0 ] || [ "$LINEIMGS" = "" ] ) && return 1;

  local ed="";
  local FEATS="";

  ### Process each line ###
  local oklines="0";
  local n;
  for n in $(seq 1 $(echo "$LINEIMGS" | wc -l)); do
    local ff=$(echo "$LINEIMGS" | sed -n $n'{s|\.png$||;p;}');
    local id=$(echo "$ff" | sed 's|.*\.||');

    echo "$FN: processing line image ${ff}.png";

    ### Clean and trim line image ###
    imglineclean $htrsh_imglineclean_opts ${ff}.png ${ff}_clean.png 2>&1;
    [ "$?" != 0 ] &&
      echo "$FN: error: problems cleaning line image: ${ff}.png" 1>&2 &&
      continue;

    local bbox=$(identify -format "%wx%h%X%Y" ${ff}_clean.png);
    local bboxsz=$(echo "$bbox" | sed 's|x| |; s|+.*||;');
    local bboxoff=$(echo "$bbox" | sed 's|[0-9]*x[0-9]*||; s|+| |g;');

    ### Estimate slope, slant and affine matrices ###
    local slope="";
    local slant="";
    [ "$htrsh_feat_deslope" = "yes" ] &&
      slope=$(imageSlope -i ${ff}_clean.png -o ${ff}_deslope.png -v 1 -s 10000 2>&1 \
               | sed -n '/slope medio:/{s|.* ||;p;}');
      #slope=$(convert ${ff}_clean.png +repage -flatten \
      #         -deskew 40% -print '%[deskew:angle]\n' \
      #         -trim +repage ${ff}_deslope.png);

    [ "$htrsh_feat_deslant" = "yes" ] &&
      slant=$(imageSlant -v 1 -g -i ${ff}_deslope.png -o ${ff}_deslant.png 2>&1 \
                | sed -n '/Slant medio/{s|.*: ||;p;}');

    [ "$slope" = "" ] && slope="0";
    [ "$slant" = "" ] && slant="0";

    local affine=$(echo "
      h = [ $bboxsz ];
      w = h(1);
      h = h(2);
      co = cos(${slope}*pi/180);
      si = sin(${slope}*pi/180);
      s = tan(${slant}*pi/180);
      R0 = [ co,  si, 0 ; -si, co, 0; 0, 0, 1 ];
      R1 = [ co, -si, 0 ;  si, co, 0; 0, 0, 1 ];
      S0 = [ 1, 0, 0 ;  s, 1, 0 ; 0, 0, 1 ];
      S1 = [ 1, 0, 0 ; -s, 1, 0 ; 0, 0, 1 ];
      A0 = R0*S0;
      A1 = S1*R1;

      %mn = round(min([0 0 1; w-1 h-1 1; 0 h-1 1; w-1 0 1]*A0))-1; % Jv3pT: incorrect 5 out of 1117 = 0.45%

      save('${ff}_affine.mat','A0','A1');

      printf('%.12g,%.12g,%.12g,%.12g,%.12g,%.12g\n',
        A0(1,1), A0(1,2), A0(2,1), A0(2,2), A0(3,1), A0(3,2) );
      " | octave -q -H);

    ### Apply affine transformation to image ###
    local mn;
    #if [ "$affine" = "1,0,0,1,0,0" ]; then
    # @todo This doesn't work since offset of _clean.png and _affine.png differs, is off(3:4) still necessary?
    #  ln -s $(echo "$ff" | sed 's|.*/||')_clean.png ${ff}_affine.png;
    #  mn="0,0";
    #  #mn="-1,-1";
    #else
      mn=$(convert ${ff}_clean.png +repage -flatten \
             -virtual-pixel white +distort AffineProjection ${affine} \
             -shave 1x1 -format %X,%Y -write info: \
             +repage -trim ${ff}_affine.png);
    #fi

    ### Add left and right padding ###
    local PADpx=$(echo $IMRES $htrsh_feat_padding | awk '{printf("%.0f",$1*$2/10)}');
    convert ${ff}_affine.png +repage \
      -bordercolor white -border ${PADpx}x \
      +repage ${ff}_fea.png;

    ### Compute features parallelogram ###
    local fpgram=$(echo "
      load('${ff}_affine.mat');

      off = [ $(identify -format %w,%h,%X,%Y ${ff}_affine.png) ];
      w = off(1);
      h = off(2);

      mn = [ $mn ];
      off = off(3:4) + mn(1:2);

      feaWin = $htrsh_dotmatrix_win;
      feaShift = $htrsh_dotmatrix_shift;

      numFea = size([-feaWin-${PADpx}:feaShift:w+${PADpx}+1],2);
      xmin = -feaWin/2-${PADpx};
      xmax = xmin+(numFea-1)*feaShift;

      pt0 = [ $bboxoff 0 ] + [ [ xmin 0   ]+off 1 ] * A1 ;
      pt1 = [ $bboxoff 0 ] + [ [ xmax 0   ]+off 1 ] * A1 ;
      pt2 = [ $bboxoff 0 ] + [ [ xmax h-1 ]+off 1 ] * A1 ;
      pt3 = [ $bboxoff 0 ] + [ [ xmin h-1 ]+off 1 ] * A1 ;

      printf('%g,%g %g,%g %g,%g %g,%g\n',
        pt0(1), pt0(2),
        pt1(1), pt1(2),
        pt2(1), pt2(2),
        pt3(1), pt3(2) );
      " | octave -q -H);

    ### Prepare information to add to XML ###
    #ed="$ed -i '//*[@id=\"$id\"]/_:Coords' -t attr -n bbox -v '$bbox'";
    #ed="$ed -i '//*[@id=\"$id\"]/_:Coords' -t attr -n slope -v '$slope'";
    #[ "$htrsh_feat_deslant" = "yes" ] &&
    #ed="$ed -i '//*[@id=\"$id\"]/_:Coords' -t attr -n slant -v '$slant'";
    ed="$ed -i '//*[@id=\"$id\"]/_:Coords' -t attr -n fpgram -v '$fpgram'";

    ### Compute detailed contours if requested ###
    if [ "$htrsh_feat_contour" = "yes" ]; then
      local pts=$(imgccomp -V1 -NJS -A 0.5 -D $htrsh_feat_dilradi -R 5,2,2,2 ${ff}_clean.png);
      ed="$ed -i '//*[@id=\"$id\"]/_:Coords' -t attr -n fcontour -v '$pts'";
    fi 2>&1;

    local FEATOP="";
    if [ "$htrsh_feat_normxheight" != "" ]; then
      FEATOP=$(xmlstarlet sel -t -v "//*[@id=\"$id\"]/@custom" "$XML" 2>/dev/null \
        | sed -n '/x-height:/ { s|.*x-height:\([^;]*\).*|\1|; s|px$||; p; }' );
      [ "$FEATOP" != "" ] && FEATOP="-xh $FEATOP";
    fi

    ### Extract features ###
    htrsh_extract_feats "${ff}_fea.png" "$ff.fea" $FEATOP;
    [ "$?" != 0 ] && return 1;

    echo "$ff.fea" >> "$FEATLST";

    oklines=$((oklines+1));

    [ "$PBASE" != "" ] && FEATS=$( echo "$FEATS"; echo "${ff}.fea"; );

    ### Remove temporal files ###
    [ "$htrsh_keeptmp" -lt 1 ] &&
      rm -f "${ff}.png" "${ff}_clean.png" "${ff}_fea.png";
    [ "$htrsh_keeptmp" -lt 2 ] &&
      rm -f "${ff}_affine.png" "${ff}_affine.mat";
    [ "$htrsh_keeptmp" -lt 3 ] &&
      rm -f "${ff}_deslope.png" "${ff}_deslant.png";
  done

  [ "$oklines" = 0 ] &&
    echo "$FN: error: extracted features for zero lines: $XML" 1>&2 &&
    return 1;

  ### Project features if requested ###
  if [ "$PBASE" != "" ]; then
    htrsh_feats_project <( echo "$FEATS" | sed '/^$/d' ) "$PBASE" "$OUTDIR";
    [ "$?" != 0 ] && return 1;
  fi

  ### Generate new XML Page file ###
  eval xmlstarlet ed -P $ed "'$XML'" > "$XMLOUT";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems generating XML file: $XMLOUT" 1>&2 &&
    return 1;

  if [ "$htrsh_feat_contour" = "yes" ] && [ "$REPLC" = "yes" ]; then
    local ed="";
    local id;
    for id in $(xmlstarlet sel -t -m '//*/_:Coords[@fcontour]' -v ../@id -n "$XMLOUT"); do
      ed="$ed -d '//*[@id=\"${id}\"]/_:Coords/@points'";
      ed="$ed -r '//*[@id=\"${id}\"]/_:Coords/@fcontour' -v points";
    done
    eval xmlstarlet ed --inplace $ed "'$XMLOUT'";
  fi

  return 0;
}


#----------------------------------#
# Model training related functions #
#----------------------------------#

##
## Function that trains a language model and creates related files
##
htrsh_langmodel_train () {
  local FN="htrsh_langmodel_train";
  local OUTDIR=".";
  local ORDER="2";
  local TOKENIZER="cat";
  local CANONIZER="cat";
  local DIPLOMATIZER="cat";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Trains a language model and creates related files";
      echo "Usage: $FN TEXTFILE [ Options ]";
      echo "Options:";
      echo " -o ORDER        Order of the language model (def.=$ORDER)";
      echo " -d OUTDIR       Directory for output models and temporary files (def.=$OUTDIR)";
      echo " -T TOKENIZER    Tokenizer pipe command (def.=none)";
      echo " -C CANONIZER    Word canonization pipe command, e.g. convert to upper (def.=none)";
      echo " -D DIPLOMATIZER Word diplomatizer pipe command, e.g. remove expansions (def.=none)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local TXT="$1"; [ "$TXT" = "-" ] && TXT="/dev/stdin";
  shift;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-o" ]; then
      ORDER="$2";
    elif [ "$1" = "-d" ]; then
      OUTDIR="$2";
    elif [ "$1" = "-T" ]; then
      TOKENIZER="$2";
    elif [ "$1" = "-C" ]; then
      CANONIZER="$2";
    elif [ "$1" = "-D" ]; then
      DIPLOMATIZER="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  local ORDEROPTS="-order $ORDER";
  local n;
  for n in $(seq 1 $ORDER); do
    ORDEROPTS="$ORDEROPTS -ukndiscount$n";
  done

  local GAWK_CREATE_DIC='
    BEGIN {
      FS="\t";
    }
    { canonic_count[$1] ++;
      variant_count[$1][$2] ++;
      variant_models[$1][$2] = $3;
    }
    END {
      printf( "\"<s>\"\t[]\t1\t@\n" );
      printf( "\"</s>\"\t[]\n" );
      for( canonic in canonic_count ) {
        wcanonic = canonic;
        gsub( "\x22", "\\\x22", wcanonic );
        gsub( "\x27", "\\\x27", wcanonic );
        for( variant in variant_count[canonic] ) {
          vprob = sprintf("%g",variant_count[canonic][variant]/canonic_count[canonic]);
          if( ! match(vprob,/\./) )
            vprob = ( vprob ".0" );
          printf( "\"%s\"\t[%s]\t%s\t", wcanonic, variant, vprob );
          N = split( variant_models[canonic][variant], txt, "" );
          for( n=1; n<=N; n++ ) {
            printf( n==1 ? "" : " " );
            switch( txt[n] ) {
            case "@":    printf( "{at}" );       break;
            case "&":    printf( "{amp}" );      break;
            case "<":    printf( "{lt}" );       break;
            case ">":    printf( "{gt}" );       break;
            case "{":    printf( "{lbrace}" );   break;
            case "}":    printf( "{rbrace}" );   break;
            case "_":    printf( "{_}" );        break;
            case "\x22": printf( "{dquote}" );   break;
            case "\x27": printf( "{squote}" );   break;
            default:     printf( "%s", txt[n] ); break;
            }
          }
          printf( " @\n" );
        }
      }
    }';

  ### Tokenize training text ###
  cat "$TXT" \
    | eval $TOKENIZER \
    > "$OUTDIR/text_tokenized.txt";

  ### Create dictionary ###
  paste \
      <( cat "$OUTDIR/text_tokenized.txt" \
           | eval $CANONIZER \
           | tee "$OUTDIR/text_canonized.txt" \
           | tr ' ' '\n' ) \
      <( cat "$OUTDIR/text_tokenized.txt" \
           | tr ' ' '\n' ) \
      <( cat "$OUTDIR/text_tokenized.txt" \
           | eval $DIPLOMATIZER \
           | tr ' ' '\n' ) \
    | gawk "$GAWK_CREATE_DIC" \
    | LC_ALL=C.UTF-8 sort \
    > "$OUTDIR/dictionary.txt";

  ### Create vocabulary ###
  awk '
    { if( $1 != "\"<s>\"" && $1 != "\"</s>\"" )
        print $1;
    }' "$OUTDIR/dictionary.txt" \
    | sed 's|^"\(.*\)"$|\1|; s|\\\(["\x27]\)|\1|g;' \
    > "$OUTDIR/vocabulary.txt";

  ### Create n-gram ###
  ngram-count -text "$OUTDIR/text_canonized.txt" -vocab "$OUTDIR/vocabulary.txt" \
      -lm - $ORDEROPTS \
    | sed 's|\(["\x27]\)|\\\1|g' \
    > "$OUTDIR/langmodel_${ORDER}-gram.arpa";

  HBuild -n "$OUTDIR/langmodel_${ORDER}-gram.arpa" -s "<s>" "</s>" \
    "$OUTDIR/dictionary.txt" "$OUTDIR/langmodel_${ORDER}-gram.lat";

  rm "$OUTDIR/vocabulary.txt";

  return 0;
}

##
## Function that prints to stdout HMM prototype(s) in HTK format
##
htrsh_hmm_proto () {
  local FN="htrsh_hmm_proto";
  local PNAME="proto";
  local GLOBAL="";
  local MEAN="";
  local VARIANCE="";
  local DISCR="no";
  local RAND="no";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Prints to stdout HMM prototype(s) in HTK format";
      echo "Usage: $FN (DIMS|CODES) STATES [ Options ]";
      echo "Options:";
      echo " -n PNAME     Proto name(s), if several separated by '\n' (def.=$PNAME)";
      echo " -g GLOBAL    Include given global options string (def.=none)";
      echo " -m MEAN      Use given mean vector (def.=zeros)";
      echo " -v VARIANCE  Use given variance vector (def.=ones)";
      echo " -D (yes|no)  Whether proto should be discrete (def.=$DISCR)";
      echo " -R (yes|no)  Whether to randomize (def.=$RAND)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local DIMS="$1";
  local STATES="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-n" ]; then
      PNAME="$2";
    elif [ "$1" = "-g" ]; then
      GLOBAL="$2";
    elif [ "$1" = "-m" ]; then
      MEAN="$2";
    elif [ "$1" = "-v" ]; then
      VARIANCE="$2";
    elif [ "$1" = "-D" ]; then
      DISCR="$2";
    elif [ "$1" = "-R" ]; then
      RAND="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Print global options ###
  if [ "$DISCR" = "yes" ]; then
    echo '~o <DISCRETE> <STREAMINFO> 1 1';
  else
    if [ "$GLOBAL" != "off" ]; then
      echo "~o";
      echo "<STREAMINFO> 1 $DIMS";
      echo "<VECSIZE> $DIMS<NULLD><USER><DIAGC>";
    fi

    [ "$MEAN" = "" ] &&
      MEAN=$(echo $DIMS | awk '{for(d=$1;d>0;d--)printf(" 0.0")}');

    [ "$VARIANCE" = "" ] &&
      VARIANCE=$(echo $DIMS | awk '{for(d=$1;d>0;d--)printf(" 1.0")}');
  fi

  [ "$GLOBAL" != "" ] && [ "$GLOBAL" != "off" ] &&
    echo "$GLOBAL";

  ### Print prototype(s) ###
  echo "$PNAME" \
    | awk -v D=$DIMS -v SS=$STATES \
          -v MEAN="$MEAN" -v VARIANCE="$VARIANCE" \
          -v DISCR=$DISCR -v RAND=$RAND '
        BEGIN { srand('$RANDOM'); }
        { S = NF > 1 ? $2 : SS;
          printf("~h \"%s\"\n",$1);
          printf("<BEGINHMM>\n");
          printf("<NUMSTATES> %d\n",S+2);
          for(s=1;s<=S;s++) {
            printf("<STATE> %d\n",s+1);
            if(DISCR=="yes") {
              printf("<NUMMIXES> %d\n",D);
              printf("<DPROB>");
              if(RAND=="yes") {
                tot=0;
                for(d=1;d<=D;d++)
                  tot+=rnd[d]=rand();
                for(d=1;d<=D;d++) {
                  v=int(sprintf("%.0f",-2371.8*log(rnd[d]/tot)));
                  printf(" %d",v>32767?32767:v);
                }
                delete rnd;
              }
              else
                for(d=1;d<=D;d++)
                  printf(" %.0f",-2371.8*log(1/D));
              printf("\n");
            }
            else {
              printf("<MEAN> %d\n",D);
              if(RAND=="yes") {
                for(d=1;d<=D;d++)
                  printf(d==1?"%g":" %g",(rand()-0.5)/10);
                printf("\n");
                printf("<VARIANCE> %d\n",D);
                for(d=1;d<=D;d++)
                  printf(d==1?"%g":" %g",1+(rand()-0.5)/10);
                printf("\n");
              }
              else {
                printf("%s\n",MEAN);
                printf("<VARIANCE> %d\n",D);
                printf("%s\n",VARIANCE);
              }
            }
          }
          printf("<TRANSP> %d\n",S+2);
          printf(" 0.0 1.0");
          for(a=2;a<=S+1;a++)
            printf(" 0.0");
          printf("\n");
          for(aa=1;aa<=S;aa++) {
            for(a=0;a<=S+1;a++)
              if(RAND=="yes") {
                if( a == aa ) {
                  pr=rand();
                  pr=pr<1e-9?1e-9:pr;
                  printf(" %g",pr);
                }
                else if( a == aa+1 )
                  printf(" %g",1-pr);
                else
                  printf(" 0.0");
              }
              else {
                if( a == aa )
                  printf(" 0.6");
                else if( a == aa+1 )
                  printf(" 0.4");
                else
                  printf(" 0.0");
              }
            printf("\n");
          }
          for(a=0;a<=S+1;a++)
            printf(" 0.0");
          printf("\n");
          printf("<ENDHMM>\n");
        }';

  return 0;
}

##
## Function that trains HMMs for a given feature list and mlf
##
htrsh_hmm_train () {
  local FN="htrsh_hmm_train";
  local OUTDIR=".";
  local CODES="0";
  local PROTO="";
  local KEEPITERS="yes";
  local RESUME="yes";
  local RAND="no";
  local THREADS="1";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Trains HMMs for a given feature list and mlf";
      echo "Usage: $FN FEATLST MLF [ Options ]";
      echo "Options:";
      echo " -d OUTDIR    Directory for output models and temporary files (def.=$OUTDIR)";
      echo " -c CODES     Train discrete model with given codebook size (def.=false)";
      echo " -P PROTO     Use PROTO as initialization prototype (def.=false)";
      echo " -k (yes|no)  Whether to keep models per iteration, including initialization (def.=$KEEPITERS)";
      echo " -r (yes|no)  Whether to resume previous training, looks for models per iteration (def.=$RESUME)";
      echo " -R (yes|no)  Whether to randomize initialization prototype (def.=$RAND)";
      echo " -T THREADS   Threads for parallel processing, max. 99 (def.=$THREADS)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local FEATLST="$1";
  local MLF="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      OUTDIR="$2";
    elif [ "$1" = "-c" ]; then
      CODES="$2";
    elif [ "$1" = "-P" ]; then
      PROTO="$2";
    elif [ "$1" = "-k" ]; then
      KEEPITERS="$2";
    elif [ "$1" = "-r" ]; then
      RESUME="$2";
    elif [ "$1" = "-R" ]; then
      RAND="$2";
    elif [ "$1" = "-T" ]; then
      THREADS=$(echo $2 | awk '{ v=0.0+$1; printf( "%d", v>99 ? 99 : (v<1?1:v) ) }');
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if [ ! -e "$FEATLST" ]; then
    echo "$FN: error: feature list not found: $FEATLST" 1>&2;
    return 1;
  elif [ ! -e "$MLF" ]; then
    echo "$FN: error: MLF file not found: $MLF" 1>&2;
    return 1;
  elif [ "$PROTO" != "" ] && [ ! -e "$PROTO" ]; then
    echo "$FN: error: initialization prototype not found: $PROTO" 1>&2;
    return 1;
  fi

  local DIMS=$(HList -z -h $(head -n 1 "$FEATLST") | sed -n '/Num Comps:/{s|.*Num Comps: *||;s| .*||;p;}');
  [ "$CODES" != 0 ] && [ $(HList -z -h "$(head -n 1 "$FEATLST")" | grep DISCRETE_K | wc -l) = 0 ] &&
    echo "$FN: error: features are not discrete" 1>&2 &&
    return 1;

  local HMMLST=$(cat "$MLF" \
                   | sed '/^#!MLF!#/d; /^"\*\//d; /^\.$/d; s|^"\(.*\)"$|\1|;' \
                   | LC_ALL=C.UTF-8 sort -u);

  if [ "$THREADS" -gt 1 ]; then
    rm -f "$OUTDIR/train_feats_part_"*;
    THREADS=$(htrsh_randsplit "$THREADS" "$FEATLST" "$OUTDIR/train_feats_part_%d" 1);
    [ "$THREADS" = "" ] &&
      echo "$FN: error: problems splitting list: $FEATLST" 1>&2 &&
      return 1;
  fi

  ### Discrete training ###
  if [ "$CODES" -gt 0 ]; then
    ### Initialization ###
    if [ "$PROTO" != "" ]; then
      cp -p "$PROTO" "$OUTDIR/Macros_hmm.gz";
    else
      htrsh_hmm_proto "$CODES" "$htrsh_hmm_states" -D yes -n "$HMMLST" -R $RAND \
        | gzip > "$OUTDIR/Macros_hmm.gz";
    fi

    [ "$KEEPITERS" = "yes" ] &&
      cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_i00.gz";

    # @todo train with viterbi
    #htrsh_hmm_proto "$CODES" "$htrsh_hmm_states" -D yes -n "$HMMLST" -R $RAND | gzip > "$OUTDIR/Macros_hmm.gz";
    #htrsh_hmm_proto "$CODES" "$htrsh_hmm_states" -D yes -R $RAND | gzip > proto.gz;
    #HInit -T 1 -C <( echo "$htrsh_HTK_config" ) -i $htrsh_hmm_iter -S "$FEATLST" -I "$MLF" -H "Macros_hmm.gz" proto.gz

    ### Iterate ###
    local i;
    for i in $(seq -f %02.0f 1 $htrsh_hmm_iter); do
      echo "$FN: info: HERest iteration $i" 1>&2;
      HERest $htrsh_HTK_HERest_opts -C <( echo "$htrsh_HTK_config" ) \
        -S "$FEATLST" -I "$MLF" -H "$OUTDIR/Macros_hmm.gz" <( echo "$HMMLST" ) 1>&2;
      if [ "$?" != 0 ]; then
        echo "$FN: error: problem with HERest" 1>&2;
        mv "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_i${i}_err.gz";
        return 1;
      fi
      [ "$KEEPITERS" = "yes" ] &&
        cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_i$i.gz";
    done
    [ "$KEEPITERS" = "yes" ] &&
      cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_i$i.gz";

  ### Continuous training ###
  else
    ### Initialization ###
    if [ "$PROTO" != "" ]; then
      cp -p "$PROTO" "$OUTDIR/Macros_hmm.gz";

      [ "$KEEPITERS" = "yes" ] &&
        cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_g001_i00.gz";

    elif [ "$RESUME" != "no" ] && [ -e "$OUTDIR/Macros_hmm_g001_i00.gz" ]; then
      RESUME="Macros_hmm_g001_i00.gz";
      cp -p "$OUTDIR/Macros_hmm_g001_i00.gz" "$OUTDIR/Macros_hmm.gz";

    else
      RESUME="no";

      # @todo implement random ?

      htrsh_hmm_proto "$DIMS" 1 | gzip > "$OUTDIR/proto";
      HCompV $htrsh_HTK_HCompV_opts -C <( echo "$htrsh_HTK_config" ) \
        -S "$FEATLST" -M "$OUTDIR" "$OUTDIR/proto" 1>&2;

      local GLOBAL=$(< "$OUTDIR/vFloors");
      local MEAN=$(zcat "$OUTDIR/proto" | sed -n '/<MEAN>/{N;s|.*\n||;p;q;}');
      local VARIANCE=$(zcat "$OUTDIR/proto" | sed -n '/<VARIANCE>/{N;s|.*\n||;N;p;q;}');

      htrsh_hmm_proto "$DIMS" "$htrsh_hmm_states" -n "$HMMLST" \
          -g "$GLOBAL" -m "$MEAN" -v "$VARIANCE" \
        | gzip \
        > "$OUTDIR/Macros_hmm.gz";

      [ "$KEEPITERS" = "yes" ] &&
        cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_g001_i00.gz";
    fi

    local TS=$(($(date +%s%N)/1000000));

    ### Training loop ###
    local g="1";
    local gg i;
    while [ "$g" -le "$htrsh_hmm_nummix" ]; do
      ### Duplicate Gaussians ###
      if [ "$g" -gt 1 ] && ! ( [ "$RESUME" != "no" ] && [ -e "$OUTDIR/Macros_hmm_g${gg}_i$i.gz" ] ); then
        echo "$FN: info: duplicating Gaussians to $g" 1>&2;
        HHEd $htrsh_HTK_HHEd_opts -C <( echo "$htrsh_HTK_config" ) -H "$OUTDIR/Macros_hmm.gz" \
          -M "$OUTDIR" <( echo "MU $g {*.state[2-$((htrsh_hmm_states-1))].mix}" ) \
          <( echo "$HMMLST" ) 1>&2;
      fi

      ### Re-estimation iterations ###
      local gg=$(printf %.3d $g);
      for i in $(seq -f %02.0f 1 $htrsh_hmm_iter); do
        if [ "$RESUME" != "no" ] && [ -e "$OUTDIR/Macros_hmm_g${gg}_i$i.gz" ]; then
          RESUME="Macros_hmm_g${gg}_i$i.gz";
          cp -p "$OUTDIR/Macros_hmm_g${gg}_i$i.gz" "$OUTDIR/Macros_hmm.gz";
          continue;
        fi

        [ "$RESUME" != "no" ] && [ "$RESUME" != "yes" ] &&
          echo "$FN: info: resuming from $RESUME" 1>&2;
        RESUME="no";

        echo "$FN: info: $g Gaussians HERest iteration $i" 1>&2;

        ### Multi-thread ###
        if [ "$THREADS" -gt 1 ]; then
          local TMPDIR="$OUTDIR";
          htrsh_run_parallel 1:$THREADS HERest \
            $htrsh_HTK_HERest_opts -C <( echo "$htrsh_HTK_config" ) \
            -S "$OUTDIR/train_feats_part_JOBID" -p JOBID \
            -I "$MLF" -H "$OUTDIR/Macros_hmm.gz" -M "$OUTDIR" <( echo "$HMMLST" ) 1>&2;
          [ "$?" != 0 ] &&
            echo "$FN: error: problem with parallel HERest" 1>&2 &&
            return 1;
          HERest $htrsh_HTK_HERest_opts -C <( echo "$htrsh_HTK_config" ) \
            -p 0 -H "$OUTDIR/Macros_hmm.gz" <( echo "$HMMLST" ) "$OUTDIR/"*.acc 1>&2;
          [ "$?" != 0 ] &&
            echo "$FN: error: problem with accumulation HERest" 1>&2 &&
            return 1;
          rm "$OUTDIR/"*.acc;

        ### Single thread ###
        else
          HERest $htrsh_HTK_HERest_opts -C <( echo "$htrsh_HTK_config" ) \
            -S "$FEATLST" -I "$MLF" -H "$OUTDIR/Macros_hmm.gz" <( echo "$HMMLST" ) 1>&2;
          [ "$?" != 0 ] &&
            echo "$FN: error: problem with HERest" 1>&2 &&
            return 1;
        fi

        local TE=$(($(date +%s%N)/1000000)); echo "$FN: time g=2^$((g-1)) i=$i: $((TE-TS)) ms" 1>&2; TS="$TE";

        [ "$KEEPITERS" = "yes" ] &&
          cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_g${gg}_i$i.gz";
      done

      cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_g${gg}_i$i.gz";
      g=$((g+g));
    done

    [ "$RESUME" != "no" ] && [ "$RESUME" != "yes" ] &&
      echo "$FN: warning: model already trained $RESUME" 1>&2;

    echo "$OUTDIR/Macros_hmm_g${gg}_i$i.gz";
  fi

  rm -f "$OUTDIR/proto" "$OUTDIR/vFloors" "$OUTDIR/Macros_hmm.gz";
  rm -f "$OUTDIR/train_feats_part_"*;

  return 0;
}


#----------------------------#
# Decoding related functions #
#----------------------------#

##
## Function that executes N parallel threads of HVite or HLRescore for a given feature list
##
htrsh_hvite_parallel () {
  local FN="htrsh_hvite_parallel";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Executes N parallel threads of HVite or HLRescore for a given feature list";
      echo "Usage: $FN THREADS (HVite|HLRescore) OPTIONS";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local THREADS="$1";
  local CMD=("$2");
  shift 2;

  local TMP="${TMPDIR:-.}";
  TMP=$(mktemp -d --tmpdir="$TMP" ${FN}_XXXXX);
  [ ! -d "$TMP" ] &&
    echo "$FN: error: failed to create temporal files" 1>&2 &&
    return 1;
  local TMPDIR="$TMP";
  local TMPRND=$(echo "$TMP" | sed 's|.*_||');

  local ARGN="1";
  local FEATLST="";
  local MLF="";
  while [ $# -gt 0 ]; do
    CMD[$ARGN]="$1";
    ARGN=$((ARGN+1));
    if [ "$1" = "-S" ]; then
      FEATLST="$2";
      CMD[$ARGN]="{@}";
      ARGN=$((ARGN+1));
      shift 1;
    elif [ "$1" = "-i" ]; then
      MLF="$2";
      CMD[$ARGN]="$TMP/mlf_{#}";
      ARGN=$((ARGN+1));
      shift 1;
    fi
    shift 1;
  done

  if [ "$CMD" != "HVite" ] && [ "$CMD" != "HLRescore" ]; then
    echo "$FN: error: command has to be either HVite or HLRescore" 1>&2;
    return 1;
  elif [ "$FEATLST" = "" ]; then
    echo "$FN: error: a feature list using option -S must be given" 1>&2;
    return 1;
  elif [ ! -e "$FEATLST" ]; then
    echo "$FN: error: feature list file not found: $FEATLST" 1>&2;
    return 1;
  fi

  sort -R "$FEATLST" \
    | htrsh_run_parallel_list "$THREADS" - "${CMD[@]}" 1>&2;
  [ "$?" != 0 ] &&
    echo "$FN: error: problems executing $CMD ($TMPRND)" 1>&2 &&
    return 1;

  [ "$MLF" != "" ] &&
    { echo "#!MLF!#";
      sed '/^#!MLF!#/d' "$TMP/mlf_"*;
    } > "$MLF";

  rm -r "$TMP";
  return 0;
}

##
## Function that fixes the quotes of rec MLFs
##
htrsh_fix_rec_mlf_quotes () {
  local FN="htrsh_fix_rec_mlf_quotes";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Fixes the quotes of rec MLFs";
      echo "Usage: $FN MLF";
    } 1>&2;
    return 1;
  fi

  local MLF="$1"; [ "$MLF" = "-" ] && MLF="/dev/stdin";

  gawk '
    { if( NF >= 3 ) {
        if( match($3,/^\x27.*\x27$/) )
          $3 = gensub( /^\x27(.*)\x27$/, "\\1", "", $3 );
        if( ! match($3,/^".+"$/) )
          $3 = ("\"" gensub( /\x22/, "\\\\\x22", "g", $3 ) "\"");
      }
      print;
    }' < "$MLF";

  return 0;
}

##
## Function that replaces special HMM model names with corresponding characters
##
htrsh_fix_rec_names () {
  local FN="htrsh_fix_rec_names";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Replaces special HMM model names with corresponding characters";
      echo "Usage: $FN XMLIN";
    } 1>&2;
    return 1;
  fi

  sed -i '
    s|@| |g;
    s|{at}|@|g;
    s|{_}|_|g;
    s|{dquote}|"|g;
    s|{squote}|'"'"'|g;
    s|{amp}|\&amp;|g;
    s|{lt}|\&lt;|g;
    s|{gt}|\&gt;|g;
    s|{dash}|--|g;
    s|{lbrace}|{|g;
    s|{rbrace}|}|g;
    ' "$1";

  return 0;
}


#-----------------------------#
# Alignment related functions #
#-----------------------------#

##
## Function that prepares a rec MLF for inserting alignment information in a Page XML
##
htrsh_mlf_prepalign () {
  local FN="htrsh_mlf_prepalign";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Prepares a rec MLF for inserting alignment information in a Page XML";
      echo "Usage: $FN MLF";
    } 1>&2;
    return 1;
  fi

  gawk '
    { if( $0 != "#!MLF!#" && ! match( $0, /\.rec"$/ ) ) {
        if( $0 != "." ) {
          printf( "%s %s @\n", $1, $1 );
          PE = $2;
        }
        else
          printf( "%s %s @\n", PE, PE );
        if( match( $3, /^".*"$/ ) )
          $3 = gensub( /\\"/, "\"", "g", gensub( /^"(.+)"$/, "\\1", "", $3 ) );
     }
     print;
   }' "$1";

  return $?;
}

##
## Function that inserts alignment information in an XML Page given a rec MLF
##
htrsh_pagexml_insertalign_lines () {
  local FN="htrsh_pagexml_insertalign_lines";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Inserts alignment information in an XML Page given a rec MLF";
      echo "Usage: $FN XML MLF";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  local MLF="$2";

  if ! [ -e "$XML" ]; then
    echo "$FN: error: XML Page file not found: $XML" 1>&2;
    return 1;
  elif ! [ -e "$MLF" ]; then
    echo "$FN: error: MLF file not found: $MLF" 1>&2;
    return 1;
  fi

  ### Check XML file and image ###
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT;
  htrsh_pageimg_info "$XML" noimg;
  [ "$?" != 0 ] && return 1;

  ### Prepare command to add alignments to XML ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): generating Page XML with alignments ..." 1>&2;

  local ids=$( sed -n '/\/'"$IMBASE"'\.[^.]\+\.[^.]\+\.rec"$/{ s|.*\.\([^.]\+\)\.rec"$|\1|; p; }' "$MLF" );

  #local TS=$(($(date +%s%N)/1000000));

  local aligns=$(
    sed -n '/\/'"$IMBASE"'\.[^.]\+\.[^.]\+\.rec"$/,/^\.$/p' "$MLF" \
      | awk '
          { if( FILENAME != "-" )
              ids[$0] = "";
            else {
              if( match( $0, /\.rec"$/ ) )
                id = gensub(/.*\.([^.]+)\.rec"$/, "\\1", "", $0 );
              else if( $0 != "." && id in ids ) {
                NF = 3;
                $2 = sprintf( "%.0f", $2/100000-1 );
                $1 = sprintf( "%.0f", $1==0 ? 0 : $1/100000-1 );
                $1 = ( id " " $1 );
                print;
              }
            }
          }' <( echo "$ids" ) -
      );

  local cmd="xmlstarlet sel -t";
  local id;
  for id in $ids; do
    cmd="$cmd -o ' ' -v '//*[@id=\"$id\"]/_:Coords/@fpgram' -o ' ;'";
  done

  local acoords=$(
    echo "
      fpgram = [ "$( eval $cmd "'$XML'" )" ];
      aligns = [ "$(
        echo "$aligns" \
          | awk '
              { if( FILENAME != "-" )
                  rid[$1] = FNR;
                else
                  printf("%s,%s\n",rid[$1],$3);
              }' <( echo "$ids" ) - \
          | sed '$!s|$|;|' \
          | tr -d '\n'
          )" ];

      for l = unique(aligns(:,1))'
        a = [ aligns( aligns(:,1)==l, 2 ) ];
        a = [ 0 a(1:end-1)'; a' ]';
        f = reshape(fpgram(l,:),2,4)';

        dx = ( f(2,1)-f(1,1) ) / a(end) ;
        dy = ( f(2,2)-f(1,2) ) / a(end) ;

        xup = f(1,1) + dx*a;
        yup = f(1,2) + dy*a;
        xdown = f(4,1) + dx*a;
        ydown = f(4,2) + dy*a;

        for n = 1:size(a,1)
          printf('%d %g,%g %g,%g %g,%g %g,%g\n',
            l,
            xdown(n,1), ydown(n,1),
            xup(n,1), yup(n,1),
            xup(n,2), yup(n,2),
            xdown(n,2), ydown(n,2) );
        end
      end" \
    | octave -q -H \
    | awk '
        { if( FILENAME != "-" )
            rid[FNR] = $1;
          else {
            $1 = rid[$1];
            print;
          }
        }' <( echo "$ids" ) - ;
    );

  #local TE=$(($(date +%s%N)/1000000)); echo "time 0: $((TE-TS)) ms" 1>&2; TS="$TE";

  [ "$htrsh_align_isect" = "yes" ] &&
    local size=$(xmlstarlet sel -t -v //@imageWidth -o x -v //@imageHeight "$XML");

  cmd="xmlstarlet ed -P";

  local n=0;
  for id in $ids; do
    n=$((n+1));
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): alignments for line $n (id=$id) ..." 1>&2;

    cmd="$cmd -d '//*[@id=\"$id\"]/_:Word'";

    [ "$htrsh_align_isect" = "yes" ] &&
      local contour=$(xmlstarlet sel -t -v '//*[@id="'$id'"]/_:Coords/@points' "$XML");

    local align=$(echo "$aligns" | sed -n "/^$id /{ s|^$id ||; p; }");
    [ "$align" = "" ] && continue;
    local coords=$(echo "$acoords" | sed -n "/^$id /{ s|^$id ||; p; }");

    #TE=$(($(date +%s%N)/1000000)); echo "time 1: $((TE-TS)) ms" 1>&2; TS="$TE";

    ### Word level alignments ###
    local W=$(echo "$align" | grep ' @$' | wc -l); W=$((W-1));
    local w;
    for w in $(seq 1 $W); do
      #TE=$(($(date +%s%N)/1000000)); echo "time 2: $((TE-TS)) ms" 1>&2; TS="$TE";
      local ww=$(printf %.2d $w);
      local pS=$(echo "$align" | grep -n ' @$' | sed -n "$w{s|:.*||;p;}"); pS=$((pS+1));
      local pE=$(echo "$align" | grep -n ' @$' | sed -n "$((w+1)){s|:.*||;p;}"); pE=$((pE-1));
      local pts;
      if [ "$pS" = "$pE" ]; then
        pts=$(echo "$coords" | sed -n "${pS}p");
      else
        pts=$(echo "$coords" \
          | sed -n "$pS{s| [^ ]* [^ ]*$||;p;};$pE{s|^[^ ]* [^ ]* ||;p;};" \
          | tr '\n' ' ' \
          | sed 's| $||');
      fi
      #TE=$(($(date +%s%N)/1000000)); echo "time 3: $((TE-TS)) ms" 1>&2; TS="$TE";

      if [ "$htrsh_align_isect" = "yes" ]; then
        local AWK_ISECT='
          BEGIN {
            printf( "convert -fill white -stroke white" );
          }
          { if( NR == 1 ) {
              mn_x=$1; mx_x=$1;
              mn_y=$2; mx_y=$2;
              for( n=3; n<=NF; n+=2 ) {
                if( mn_x > $n ) mn_x = $n;
                if( mx_x < $n ) mx_x = $n;
                if( mn_y > $(n+1) ) mn_y = $(n+1);
                if( mx_y < $(n+1) ) mx_y = $(n+1);
              }
              w = mx_x-mn_x+1;
              h = mx_y-mn_y+1;
            }
            printf( " \\( -size %dx%d xc:black -draw \"polyline", w, h );
            for( n=1; n<=NF; n+=2 )
              printf( " %d,%d", $n-mn_x, $(n+1)-mn_y );
            printf( "\" \\)" );
          }
          END {
            printf( " -compose darken -composite -page %s+%d+%d miff:-\n", sz, mn_x, mn_y );
          }';
        pts=$(
          eval $(
            { echo "$pts";
              echo "$contour";
            } | awk -F'[ ,]' -v sz=$size "$AWK_ISECT" ) \
            | imgccomp -V0 -JS - );
        local wpts="$pts";
      fi

      #TE=$(($(date +%s%N)/1000000)); echo "time 4: $((TE-TS)) ms" 1>&2; TS="$TE";

      cmd="$cmd -s '//*[@id=\"$id\"]' -t elem -n TMPNODE";
      cmd="$cmd -i '//TMPNODE' -t attr -n id -v '${id}_w${ww}'";
      cmd="$cmd -s '//TMPNODE' -t elem -n Coords";
      cmd="$cmd -i '//TMPNODE/Coords' -t attr -n points -v '$pts'";
      cmd="$cmd -r '//TMPNODE' -v Word";

      ### Character level alignments ###
      if [ "$htrsh_align_chars" = "yes" ]; then
        local g=1;
        local c;
        for c in $(seq $pS $pE); do
          local gg=$(printf %.2d $g);
          local pts=$(echo "$coords" | sed -n "${c}p");
          [ "$htrsh_align_isect" = "yes" ] &&
            pts=$(
              eval $(
                { echo "$pts";
                  echo "$wpts";
                } | awk -F'[ ,]' -v sz=$size "$AWK_ISECT" ) \
                | imgccomp -V0 -JS - );
            # @todo character polygons overlap slightly, possible solution: reduce width of parallelograms by 1 pixel in each side

          cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]' -t elem -n TMPNODE";
          cmd="$cmd -i '//TMPNODE' -t attr -n id -v '${id}_w${ww}_g${gg}'";
          cmd="$cmd -s '//TMPNODE' -t elem -n Coords";
          cmd="$cmd -i '//TMPNODE/Coords' -t attr -n points -v '$pts'";
          if [ "$htrsh_align_addtext" = "yes" ]; then
            local text=$(echo "$align" | sed -n "$c{s|.* ||;p;}" | tr -d '\n');
            cmd="$cmd -s '//TMPNODE' -t elem -n TextEquiv";
            cmd="$cmd -s '//TMPNODE/TextEquiv' -t elem -n Unicode -v '$text'";
          fi
          cmd="$cmd -r '//TMPNODE' -v Glyph";

          g=$((g+1));
        done
      fi

      #TE=$(($(date +%s%N)/1000000)); echo "time 5: $((TE-TS)) ms" 1>&2; TS="$TE";

      if [ "$htrsh_align_addtext" = "yes" ]; then
        local text=$(echo "$align" | sed -n "$pS,$pE{s|.* ||;p;}" | tr -d '\n');
        cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]' -t elem -n TextEquiv";
        cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]/TextEquiv' -t elem -n Unicode -v '$text'";
        #TE=$(($(date +%s%N)/1000000)); echo "time 6: $((TE-TS)) ms" 1>&2; TS="$TE";
      fi
    done

    cmd="$cmd -m '//*[@id=\"$id\"]/_:TextEquiv' '//*[@id=\"$id\"]'";
  done

  ### Create new XML including alignments ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): edit XML ..." 1>&2;
  eval $cmd "'$XML'";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating XML file: $XMLOUT" 1>&2 &&
    return 1;

  return 0;
}

##
## Function that does a forced alignment at a line level for a given XML Page, feature list and model
##
htrsh_pageimg_forcealign_lines () {
  local FN="htrsh_pageimg_forcealign_lines";
  local TMPDIR=".";
  if [ $# -lt 4 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Does a forced alignment at a line level for a given XML Page, feature list and model";
      echo "Usage: $FN XMLIN FEATLST MODEL XMLOUT [ Options ]";
      echo "Options:";
      echo " -d TMPDIR    Directory for temporary files (def.=$TMPDIR)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  local FEATLST="$2";
  local MODEL="$3";
  local XMLOUT="$4";
  shift 4;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      TMPDIR="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if ! [ -e "$XML" ]; then
    echo "$FN: error: Page XML file not found: $XML" 1>&2;
    return 1;
  elif ! [ -e "$FEATLST" ]; then
    echo "$FN: error: feature list not found: $FEATLST" 1>&2;
    return 1;
  elif ! [ -e "$MODEL" ]; then
    echo "$FN: error: model file not found: $MODEL" 1>&2;
    return 1;
  fi

  ### Check XML file and image ###
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES RESSRC;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;
  local B=$(echo "$XMLBASE" | sed 's|[\[ ()]|_|g; s|]|_|g;');

  ### Create MLF from XML ###
  { echo '#!MLF!#'; htrsh_pagexml_textequiv "$XML" -f mlf-chars; } > "$TMPDIR/$B.mlf";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating MLF file: $XML" 1>&2 &&
    return 1;

  ### Create auxiliary files: HMM list and dictionary ###
  local HMMLST=$(zcat "$MODEL" | sed -n '/^~h "/{ s|^~h "||; s|"$||; p; }');
  local DIC=$(echo "$HMMLST" | awk '{printf("\"%s\" [%s] 1.0 %s\n",$1,$1,$1)}');

  ### Do forced alignment with HVite ###
  HVite $htrsh_HTK_HVite_opts -C <( echo "$htrsh_HTK_config" ) -H "$MODEL" -S "$FEATLST" -m -I "$TMPDIR/$B.mlf" -i "$TMPDIR/${B}_aligned.mlf" <( echo "$DIC" ) <( echo "$HMMLST" );
  [ "$?" != 0 ] &&
    echo "$FN: error: problems aligning with HVite: $XML" 1>&2 &&
    return 1;

  ### Insert alignment information in XML ###
  htrsh_pagexml_insertalign_lines "$XML" "$TMPDIR/${B}_aligned.mlf" \
    > "$XMLOUT";
  [ "$?" != 0 ] &&
    return 1;

  htrsh_fix_rec_names "$XMLOUT";

  [ "$htrsh_keeptmp" -lt 1 ] &&
    rm -f "$TMPDIR/$B.mlf" "$TMPDIR/${B}_aligned.mlf";

  return 0;
}

##
## Function that does a line by line forced alignment given only a page with baselines or contours and optionally a model
##
htrsh_pageimg_forcealign () {
  local FN="htrsh_pageimg_forcealign";
  local TS=$(date +%s);
  local TMPDIR="./_forcealign";
  local INRES="";
  local MODEL="";
  local PBASE="";
  local ENHIMG="yes";
  local DOPCA="yes";
  local KEEPTMP="no";
  local KEEPAUX="no";
  local QBORD="no";
  local FILTER="cat";
  local SFACT="";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Does a line by line forced alignment given only a page with baselines or contours and optionally a model";
      echo "Usage: $FN XMLIN XMLOUT [ Options ]";
      echo "Options:";
      echo " -d TMPDIR    Directory for temporary files (def.=$TMPDIR)";
      echo " -i INRES     Input image resolution in ppc (def.=use image metadata)";
      echo " -m MODEL     Use given model for aligning (def.=train model for page)";
      echo " -b PBASE     Project features using given base (def.=false)";
      echo " -e (yes|no)  Whether to enhance the image using imgtxtenh (def.=$ENHIMG)";
      echo " -p (yes|no)  Whether to compute PCA for image and project features (def.=$DOPCA)";
      echo " -t (yes|no)  Whether to keep temporary directory and files (def.=$KEEPTMP)";
      echo " -a (yes|no)  Whether to keep auxiliary attributes in XML (def.=$KEEPAUX)";
      #echo " -q (yes|no)  Whether to clean quadrilateral border of regions (def.=$QBORD)";
      echo " -F FILTER    Filtering pipe command, e.g. tokenizer, transliteration, etc. (def.=none)";
      echo " -s SRES      Rescale image to SRES dpcm for processing (def.=orig.)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  local XMLOUT="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      TMPDIR=$(echo "$2" | sed '/^[./]/!s|^|./|');
    elif [ "$1" = "-i" ]; then
      INRES="$2";
    elif [ "$1" = "-m" ]; then
      MODEL="$2";
    elif [ "$1" = "-b" ]; then
      PBASE="$2";
    elif [ "$1" = "-e" ]; then
      ENHIMG="$2";
    elif [ "$1" = "-p" ]; then
      DOPCA="$2";
    elif [ "$1" = "-t" ]; then
      KEEPTMP="$2";
    elif [ "$1" = "-a" ]; then
      KEEPAUX="$2";
    elif [ "$1" = "-q" ]; then
      QBORD="$2";
    elif [ "$1" = "-F" ]; then
      FILTER="$2";
    elif [ "$1" = "-s" ]; then
      SFACT="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if [ -d "$TMPDIR" ]; then
    echo -n "$FN: temporary directory ($TMPDIR) already exists, current contents will be deleted, continue? " 1>&2;
    local RMTMP="";
    read RMTMP;
    if [ "${RMTMP:0:1}" = "y" ]; then
      rm -r "$TMPDIR";
    else
      echo "$FN: aborting ..." 1>&2;
      return 1;
    fi
  fi

  ### Check page ###
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES RESSRC;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  #local RCNT=$(xmlstarlet sel -t -v "count($htrsh_xpath_regions/_:TextEquiv/_:Unicode)" "$XML");
  local RCNT="0";
  local LCNT=$(xmlstarlet sel -t -v "count($htrsh_xpath_regions/$htrsh_xpath_lines/_:TextEquiv/_:Unicode)" "$XML");
  [ "$RCNT" = 0 ] && [ "$LCNT" = 0 ] &&
    echo "$FN: error: no TextEquiv/Unicode nodes for processing: $XML" 1>&2 &&
    return 1;

  local WGCNT=$(xmlstarlet sel -t -v 'count(//_:Word)' -o ' ' -v 'count(//_:Glyph)' "$XML");
  [ "$WGCNT" != "0 0" ] &&
    echo "$FN: warning: input already contains Word and/or Glyph information: $XML" 1>&2;

  local AREG="no"; [ "$LCNT" = 0 ] && AREG="yes";

  local B=$(echo "$XMLBASE" | sed 's|[\[ ()]|_|g; s|]|_|g;');

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): processing page: $XML";

  mkdir -p "$TMPDIR/proc";
  cp -p "$XML" "$IMFILE" "$TMPDIR/proc";
  sed 's|imageFilename="[^"/]*/|imageFilename=|' -i "$TMPDIR/proc/$XMLBASE.xml";

  ### Generate contours from baselines ###
  if [ $(xmlstarlet sel -t -v \
           "count($htrsh_xpath_regions/_:TextLine/_:Baseline)" \
           "$XML") -gt 0 ] && (
       [ "$htrsh_align_prefer_baselines" = "yes" ] ||
       [ $(xmlstarlet sel -t -v \
             "count($htrsh_xpath_regions/_:TextLine/$htrsh_xpath_coords)" \
             "$XML") = 0 ] ); then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): generating line contours from baselines ...";
    page_format_generate_contour -a 75 -d 25 \
      -p "$TMPDIR/proc/$XMLBASE.xml" \
      -o "$TMPDIR/proc/$XMLBASE.xml";
    [ "$?" != 0 ] &&
      echo "$FN: error: page_format_generate_contour failed" 1>&2 &&
      return 1;
  fi

  ### Rescale image for processing ###
  if [ "$SFACT" != "" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): rescaling image ...";
    #SFACT=$(echo "100*$SFACT/$IMRES" | bc -l);
    # @todo check support for SFACT in %
    SFACT=$(echo "$SFACT" "$IMRES" | awk '{printf("%g",match($1,"%$")?$1:100*$1/$2)}');
    mkdir "$TMPDIR/scaled";
    mv "$TMPDIR/proc/"* "$TMPDIR";
    htrsh_pageimg_resize "$TMPDIR/$XMLBASE.xml" "$TMPDIR/proc" -s "$SFACT";
  fi

  ### Clean page image ###
  if [ "$ENHIMG" = "yes" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): enhancing page image ...";
    [ "$INRES" != "" ] && INRES="-i $INRES";
    htrsh_pageimg_clean "$TMPDIR/proc/$XMLBASE.xml" "$TMPDIR" $INRES \
      > "$TMPDIR/${XMLBASE}_pageclean.log";
    [ "$?" != 0 ] &&
      echo "$FN: error: more info might be in file $TMPDIR/${XMLBASE}_pageclean.log" 1>&2 &&
      return 1;
  else
    mv "$TMPDIR/proc/"* "$TMPDIR";
  fi

  ### Clean quadrilateral borders ###
  if [ "$QBORD" = "yes" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): cleaning quadrilateral borders ...";
    htrsh_pageimg_quadborderclean "$TMPDIR/${XMLBASE}.xml" "$TMPDIR/${IMBASE}_nobord.png" -d "$TMPDIR";
    [ "$?" != 0 ] && return 1;
    mv "$TMPDIR/${IMBASE}_nobord.png" "$TMPDIR/$IMBASE.png";
  fi

  ### Extract line features ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): extracting line features ...";
  htrsh_pageimg_extract_linefeats \
    "$TMPDIR/$XMLBASE.xml" "$TMPDIR/${XMLBASE}_feats.xml" \
    -d "$TMPDIR" -l "$TMPDIR/${B}_feats.lst" \
    > "$TMPDIR/${XMLBASE}_linefeats.log";
  [ "$?" != 0 ] &&
    echo "$FN: error: more info might be in file $TMPDIR/${XMLBASE}_linefeats.log" 1>&2 &&
    return 1;

  ### Compute PCA and project features ###
  [ "$htrsh_feat" != "dotmatrix" ] && DOPCA="no";
  if [ "$PBASE" = "" ] && [ "$DOPCA" = "yes" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): computing PCA for page ...";
    PBASE="$TMPDIR/pcab.mat.gz";
    htrsh_feats_pca "$TMPDIR/${B}_feats.lst" "$PBASE" -e 1:4 -r 24;
    [ "$?" != 0 ] && return 1;
  fi
  if [ "$PBASE" != "" ]; then
    [ ! -e "$PBASE" ] &&
      echo "$FN: error: projection base file not found: $PBASE" 1>&2 &&
      return 1;
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): projecting features ...";
    htrsh_feats_project "$TMPDIR/${B}_feats.lst" "$PBASE" "$TMPDIR";
    [ "$?" != 0 ] && return 1;
  fi

  [ "$AREG" = "yes" ] &&
    htrsh_feats_catregions "$TMPDIR/${XMLBASE}_feats.xml" "$TMPDIR" > $TMPDIR/${B}_feats.lst;

  ### Train HMMs model for this single page ###
  if [ "$MODEL" = "" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): training model for page ...";
    { echo '#!MLF!#';
      htrsh_pagexml_textequiv "$TMPDIR/${XMLBASE}_feats.xml" -f mlf-chars -r $AREG -F "$FILTER";
    } > "$TMPDIR/${B}_page.mlf";
    [ "$?" != 0 ] && return 1;
    MODEL=$(
      htrsh_hmm_train "$TMPDIR/${B}_feats.lst" "$TMPDIR/${B}_page.mlf" -d "$TMPDIR" \
        2> "$TMPDIR/${XMLBASE}_hmmtrain.log"
      );
    [ "$?" != 0 ] &&
      echo "$FN: error: problems training model, more info might be in file $TMPDIR/${XMLBASE}_hmmtrain.log" 1>&2 &&
      return 1;

  ### Check that given model has all characters, otherwise add protos for these ###
  else
    local CHARCHECK=$(
            htrsh_pagexml_textequiv "$TMPDIR/${XMLBASE}_feats.xml" \
                -f mlf-chars -r $AREG -F "$FILTER" \
              | sed '/^"\*\/.*"$/d; /^\.$/d; s|^"\(.*\)"|\1|;' \
              | sort -u);
    CHARCHECK=$(
      zcat "$MODEL" \
        | sed -n '/^~h ".*"$/ { s|^~h "\(.*\)"$|\1|; p; }' \
        | awk '
            { if( FILENAME == "-" )
                model[$1] = "";
              else if( ! ( $1 in model ) )
                print;
            }' - <( echo "$CHARCHECK" ) );
    if [ "$CHARCHECK" != "" ]; then
      echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): adding missing characters ($(echo $CHARCHECK | tr ' ' ',')) to given model ...";

      local DIMS=$(HList -h -z $(head -n 1 < "$TMPDIR/${B}_feats.lst") \
                     | sed -n '/^  Num Comps:/{s|^[^:]*: *||;s| .*||;p;}');

      htrsh_hmm_proto "$DIMS" 1 | gzip > "$TMPDIR/proto";
      HCompV $htrsh_HTK_HCompV_opts -C <( echo "$htrsh_HTK_config" ) \
        -S "$TMPDIR/${B}_feats.lst" -M "$TMPDIR" "$TMPDIR/proto" 1>&2;

      local MEAN=$(zcat "$TMPDIR/proto" | sed -n '/<MEAN>/{N;s|.*\n||;p;q;}');
      local VARIANCE=$(zcat "$TMPDIR/proto" | sed -n '/<VARIANCE>/{N;s|.*\n||;N;p;q;}');
      local NEWMODEL="$TMPDIR"/$(echo "$MODEL" | sed 's|.*/||');

      { zcat "$MODEL";
        htrsh_hmm_proto "$DIMS" "$htrsh_hmm_states" -n "$CHARCHECK" \
          -g off -m "$MEAN" -v "$VARIANCE";
      } | gzip \
        > "$NEWMODEL";
      MODEL="$NEWMODEL";
    fi
  fi
  [ ! -e "$MODEL" ] &&
    echo "$FN: error: model file not found: $MODEL" 1>&2 &&
    return 1;

  ### Do forced alignment using model ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): doing forced alignment ...";
  if [ "$AREG" = "yes" ]; then
    cp "$TMPDIR/${XMLBASE}_feats.xml" "$TMPDIR/${XMLBASE}_align.xml";
    local id;
    for id in $(xmlstarlet sel -t -m "$htrsh_xpath_regions" -v @id -n "$XML"); do
      echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): aligning region $id";
      htrsh_pageimg_forcealign_region "$TMPDIR/${XMLBASE}_align.xml" "$id" \
        "$TMPDIR" "$MODEL" "$TMPDIR/${XMLBASE}_align-.xml" -d "$TMPDIR" \
        >> "$TMPDIR/${XMLBASE}_forcealign.log";
      [ "$?" != 0 ] &&
        echo "$FN: error: more info might be in file $TMPDIR/${XMLBASE}_forcealign.log" 1>&2 &&
        return 1;
      mv "$TMPDIR/${XMLBASE}_align-.xml" "$TMPDIR/${XMLBASE}_align.xml";
    done
    cp -p "$TMPDIR/${XMLBASE}_align.xml" "$XMLOUT";
  else
    htrsh_pageimg_forcealign_lines \
      "$TMPDIR/${XMLBASE}_feats.xml" "$TMPDIR/${B}_feats.lst" "$MODEL" \
      "$XMLOUT" -d "$TMPDIR" \
      > "$TMPDIR/${XMLBASE}_forcealign.log";
    [ "$?" != 0 ] &&
      echo "$FN: error: more info might be in file $TMPDIR/${XMLBASE}_forcealign.log" 1>&2 &&
      return 1;
  fi 2>&1;

  [ "$KEEPTMP" != "yes" ] && rm -r "$TMPDIR";

  local I=$(xmlstarlet sel -t -v //@imageFilename "$XML");
  local ed="-u //@imageFilename -v '$I'";
  [ "$KEEPAUX" != "yes" ] && ed="$ed -d //@fpgram -d //@fcontour";

  eval xmlstarlet ed --inplace $ed "'$XMLOUT'";

  if [ "$SFACT" != "" ]; then
    SFACT=$(echo "10000/$SFACT" | bc -l);
    cat "$XMLOUT" \
      | htrsh_pagexml_resize "$SFACT"% \
      | htrsh_pagexml_round \
      | xmlstarlet ed \
          -u //@imageWidth -v ${IMSIZE%x*} \
          -u //@imageHeight -v ${IMSIZE#*x} \
      > "$XMLOUT"~;
    mv "$XMLOUT"~ "$XMLOUT";
  fi

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): finished, $(( $(date +%s)-TS )) seconds";

  return 0;
}
