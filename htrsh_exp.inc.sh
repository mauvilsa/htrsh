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
