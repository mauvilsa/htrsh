#!/bin/bash

##
## Collection of shell functions for Handwritten Text Recognition.
##
## @version $Revision$$Date::             $
## @author Mauricio Villegas <mauvilsa@upv.es>
## @copyright Copyright(c) 2014 to the present, Mauricio Villegas (UPV)
##

[ "${BASH_SOURCE[0]}" = "$0" ] && 
  echo "htrsh.inc.sh: error: script intended for sourcing, try: . htrsh.inc.sh" 1>&2 &&
  exit 1;
[ "$(type -t htrsh_version)" = "function" ] &&
  echo "htrsh.inc.sh: warning: library already loaded, to reload first use htrsh_unload" 1>&2 &&
  return 0;

. run_parallel.inc.sh;

#-----------------------#
# Default configuration #
#-----------------------#

htrsh_keeptmp="0";

htrsh_xpath_regions='//_:TextRegion';
htrsh_xpath_lines='_:TextLine';
htrsh_xpath_coords='_:Coords[@points and @points!="0,0 0,0"]';
htrsh_xpath_textequiv='_:TextEquiv[_:Unicode and _:Unicode != ""]/_:Unicode';

htrsh_imgclean="prhlt"; # Image preprocessing technique, prhlt or ncsr
htrsh_clean_type="image"; #htrsh_clean_type="line";

htrsh_imgtxtenh_regmask="yes";               # Whether to use a region-based processing mask
htrsh_imgtxtenh_opts="-r 0.16 -w 20 -k 0.1"; # Options for imgtxtenh tool
htrsh_imglineclean_opts="-V0 -m 99%";        # Options for imglineclean tool

htrsh_feat_deslope="yes"; # Whether to correct slope per line
htrsh_feat_deslant="yes"; # Whether to correct slant of the text
htrsh_feat_padding="1.0"; # Left and right white padding in mm for line images
htrsh_feat_contour="yes"; # Whether to compute connected components contours
htrsh_feat_dilradi="0.5"; # Dilation radius in mm for contours
htrsh_feat_normxheight="18"; # Normalize x-height (if in Page) to a fixed number of pixels

htrsh_feat="dotmatrix";    # Type of features to extract
htrsh_dotmatrix_shift="2"; # Sliding window shift in px @todo make it with respect to x-height
htrsh_dotmatrix_win="20";  # Sliding window width in px @todo make it with respect to x-height
htrsh_dotmatrix_W="8";     # Width of normalized frame in px
htrsh_dotmatrix_H="32";    # Height of normalized frame in px
htrsh_dotmatrix_mom="yes"; # Whether to add moments to features

htrsh_align_chars="no";             # Whether to align at a character level
htrsh_align_dilradi="0.5";          # Dilation radius in mm for contours
htrsh_align_contour="yes";          # Whether to compute contours from the image
htrsh_align_isect="yes";            # Whether to intersect parallelograms with line contour
htrsh_align_prefer_baselines="yes"; # Whether to always generate contours from baselines
htrsh_align_addtext="yes";          # Whether to add TextEquiv to word and glyph nodes
htrsh_align_words="yes";            # Whether to align at a word level when aligning regions
htrsh_align_wordsplit="no";         # Whether to split words when aligning regions

htrsh_hmm_states="6"; # Number of HMM states (excluding special initial and final)
htrsh_hmm_nummix="4"; # Number of Gaussian mixture components per state
htrsh_hmm_iter="4";   # Number of training iterations
htrsh_hmm_type="char";
#htrsh_hmm_type="overlap";

htrsh_HTK_HERest_opts="-m 2";      # Options for HERest tool
htrsh_HTK_HCompV_opts="-f 0.1 -m"; # Options for HCompV tool
htrsh_HTK_HHEd_opts="";            # Options for HHEd tool
htrsh_HTK_HVite_opts="";           # Options for HVite tool

htrsh_HTK_config='
HMMDEFFILTER   = "gzip -dc $"
HMMDEFOFILTER  = "gzip > $"
HNETFILTER     = "gzip -dc $"
HNETOFILTER    = "gzip > $"
NONUMESCAPES   = T
STARTWORD      = "<s>"
ENDWORD        = "</s>"
';

htrsh_special_chars=$'
<gap/> {gap}
@ {at}
_ {_}
\x27 {squote}
" {dquote}
& {amp}
< {lt}
> {gt}
{ {lbrace}
} {rbrace}
';

htrsh_sed_tokenize_simplest='
  s|$\.|$*|g;
  s|\([.,:;!¡?¿+\x27´`"“”„|(){}[—–_]\)| \1 |g;
  s|\x5D| ] |g;
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
( [ "$USER" = "mvillegas" ] || [ "$USER" = "mauvilsa" ] ) &&
  htrsh_pagexsd="$HOME/work/prog/mvsh/HTR/xsd/pagecontent+.xsd";

htrsh_realpath="readlink -f";
[ $(realpath --help 2>&1 | grep relative | wc -l) != 0 ] &&
  htrsh_realpath="realpath --relative-to=.";

htrsh_infovars="XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES RESSRC";

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
htrsh_check_dependencies () {
  local FN="htrsh_check_dependencies";
  local RC="0";
  local cmd;
  for cmd in xmlstarlet convert octave HVite dotmatrix imgtxtenh imglineclean imgccomp imgpolycrop imageSlant page_format_generate_contour; do
    local c=$(which $cmd 2>/dev/null | sed '/^alias /d; s|^\t||');
    [ ! -e "$c" ] && RC="1" &&
      echo "$FN: WARNING: unable to find command: $cmd" 1>&2;
  done

  [ $(dotmatrix -h 2>&1 | grep '\--htk' | wc -l) = 0 ] && RC="1" &&
    echo "$FN: WARNING: a dotmatrix with --htk option is required" 1>&2;

  for cmd in readhtk writehtk; do
    [ $(octave -q -H --eval "which $cmd" | wc -l) = 0 ] && RC="1" &&
      echo "$FN: WARNING: unable to find octave command: $cmd" 1>&2;
  done

  if [ "$RC" = 0 ]; then
    htrsh_version;
    run_parallel_version;
    for cmd in imgtxtenh imglineclean imgccomp; do
      $cmd --version;
    done
    { printf "xmlstarlet "; xmlstarlet --version;
      convert --version | sed -n '1{ s|^Version: ||; p; }';
      octave -q --version | head -n 1;
      HVite -V | grep HVite | cat;
    } 1>&2;
  fi

  return $RC;
}


#---------------------------------#
# XML Page manipulation functions #
#---------------------------------#

##
## Function that sets TextEquiv/Unicode in an XML Page
##
htrsh_pagexml_set_textequiv () {
  local FN="htrsh_pagexml_set_textequiv";
  if [ $# -lt 3 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Sets TextEquiv/Unicode in an XML Page";
      echo "Usage: $FN XML ID TEXT [ ID2 TEXT2 ... ]";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  shift;

  ### Check XML file ###
  local $htrsh_infovars;
  htrsh_pageimg_info "$XML" noimg;
  [ "$?" != 0 ] && return 1;

  local ids=();
  local idmatch=( xmlstarlet sel -t );
  local xmledit=( xmlstarlet ed --inplace );

  while [ $# -gt 0 ]; do
    ids+=( "$1" );
    idmatch+=( -m "//*[@id='$1']" -v @id -n );
    xmledit+=( -d "//*[@id='$1']/_:TextEquiv" );
    xmledit+=( -s "//*[@id='$1']" -t elem -n TMPNODE );
    xmledit+=( -s //TMPNODE -t elem -n Unicode -v "$2" );
    xmledit+=( -r //TMPNODE -v TextEquiv );
    shift 2;
  done

  ids=$( { printf "%s\n" "${ids[@]}"; "${idmatch[@]}" "$XML"; } \
           | sort | uniq -u | tr '\n' ',' );
  [ "$ids" != "" ] &&
    echo "$FN: error: some IDs not found ($ids): $XML" 1>&2 &&
    return 1;

  "${xmledit[@]}" "$XML";
}

##
## Function that prints to stdout the TextEquiv from an XML Page file
##
htrsh_pagexml_textequiv () {
  local FN="htrsh_pagexml_textequiv";
  local SRC="lines";
  local FORMAT="raw";
  local FILTER="cat";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Prints to stdout the TextEquiv from an XML Page file";
      echo "Usage: $FN XMLFILE [ Options ]";
      echo "Options:";
      echo " -s SOURCE    Source of TextEquiv, either 'regions', 'lines' or 'words' (def.=$SRC)";
      echo " -f FORMAT    Output format among 'raw', 'mlf-chars', 'mlf-words' and 'tab' (def.=$FORMAT)";
      echo " -F FILTER    Filtering pipe command, e.g. tokenizer, transliteration, etc. (def.=none)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  shift;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-s" ]; then
      SRC="$2";
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
  local PRINT=( -v . -n );
  if [ "$SRC" = "regions" ]; then
    XPATH="$htrsh_xpath_regions/$htrsh_xpath_textequiv";
    IDop=( -o "$PG." -v ../../@id );
  elif [ "$SRC" = "words" ]; then
    XPATH="$htrsh_xpath_regions/$htrsh_xpath_lines[_:Word/$htrsh_xpath_textequiv]";
    PRINT=( -m "_:Word/$htrsh_xpath_textequiv" -o " " -v . -b -n );
    IDop=( -o "$PG." -v ../@id -o . -v @id );
  else
    XPATH="$htrsh_xpath_regions/$htrsh_xpath_lines/$htrsh_xpath_textequiv";
    IDop=( -o "$PG." -v ../../../@id -o . -v ../../@id );
  fi

  [ $(xmlstarlet sel -t -v "count($XPATH)" "$XML") = 0 ] &&
    echo "$FN: error: zero matches for xpath $XPATH on file: $XML" 1>&2 &&
    return 1;

  paste \
      <( xmlstarlet sel -t -m "$XPATH" "${IDop[@]}" -n "$XML" ) \
      <( cat "$XML" \
           | tr '\t\n' '  ' \
           | xmlstarlet sel -T -B -E utf-8 -t -m "$XPATH" "${PRINT[@]}" \
           | $FILTER ) \
    | sed '
        s|\t  *|\t|;
        s|  *$||;
        s|   *| |g;
        ' \
    | awk -F'\t' -v FORMAT=$FORMAT -v TYPE="$htrsh_hmm_type" -v SPECIAL=<( echo "$htrsh_special_chars" ) '
        BEGIN {
          if( FORMAT == "tab" )
            OFS=" ";
          while( (getline line<SPECIAL) > 0 )
            if( line != "" ) {
              n = split(line,sline," ");
              c = substr( sline[1], 1, 1 );
              SCHAR[c] = "";
              NSPECIAL++;
              SWORD[NSPECIAL] = sline[1];
              SMARK[NSPECIAL] = n == 1 ? sline[1] : sline[2] ;
            }
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
            cprev = "@";
            N = split($2,txt,"");
            for( n=1; n<=N; n++ ) {
              c = "";
              if( txt[n] in SCHAR )
                for( m=1; m<=NSPECIAL; m++ ) {
                  w = SWORD[m];
                  if( w == substr($2,n,length(w)) ) {
                    c = SMARK[m];
                    n += length(w)-1;
                    break;
                  }
                }
              if( c == "" )
                c = txt[n] == " " ? "@" : txt[n] ;
              if( TYPE == "overlap" )
                printf( ( match(cprev,/^[.0-9]/) ? "\"%s%s\"\n" : "%s%s\n" ), cprev, c );
              printf( ( match(c,/^[.0-9]/) ? "\"%s\"\n" : "%s\n" ), c );
              cprev = c;
            }
            c = "@";
            if( TYPE == "overlap" )
              printf( ( match(cprev,/^[.0-9]/) ? "\"%s%s\"\n" : "%s%s\n" ), cprev, c );
            printf( ( match(c,/^[.0-9]/) ? "\"%s\"\n" : "%s\n" ), c );
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
          printf( "%s", gensub( /^".*\/(.+)\.[lr][ae][bc]"$/, "\\1", 1, $1 ) );
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
## Function that checks and extracts basic info (XMLDIR, IMDIR, IMFILE, XMLBASE, IMBASE, IMEXT, IMSIZE, IMRES, RESSRC) from an XML Page file and respective image
##
htrsh_pageimg_info () {
  local FN="htrsh_pageimg_info";
  local XML="$1";
  local VAL=( -e ); [ "$htrsh_valschema" = "yes" ] && VAL+=( -s "$htrsh_pagexsd" );
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Checks and extracts basic info (XMLDIR, IMDIR, IMFILE, XMLBASE, IMBASE, IMEXT, IMSIZE, IMRES, RESSRC) from an XML Page file and respective image";
      echo "Usage: $FN XMLFILE";
    } 1>&2;
    return 1;
  elif [ ! -f "$XML" ]; then
    echo "$FN: error: page file not found: $XML" 1>&2;
    return 1;
  elif [ $(xmlstarlet val ${VAL[@]} "$XML" | grep ' invalid$' | wc -l) != 0 ]; then
    echo "$FN: error: invalid page file: $XML" 1>&2;
    return 1;
  elif [ $(xmlstarlet sel -t -m '//*/@id' -v . -n "$XML" 2>/dev/null | sort | uniq -d | wc -l) != 0 ]; then
    echo "$FN: error: page file has duplicate IDs: $XML" 1>&2;
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
              { if( NF > 3 ) {
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
  local $htrsh_infovars;
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
            </xsl:when>
            <xsl:when test="position() mod 2 = 0">
              <xsl:text>,</xsl:text><xsl:value-of select="number($scaleHeight)*number(.)"/>
            </xsl:when>
            <xsl:otherwise>
              <xsl:text> </xsl:text><xsl:value-of select="number($scaleWidth)*number(.)"/>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each>
      </xsl:attribute>
      </xsl:for-each>
      <xsl:apply-templates select="@*[local-name() != '"'points'"' and local-name() != '"'fpgram'"'] | node()" />
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>';

  xmlstarlet tr <( echo "$XSLT" );
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

  xmlstarlet tr <( echo "$XSLT" );
}

##
## Function that sorts Words from left to right within TextLines in an XML Page file
## (based ONLY on (xmin+xmax)/2 of the word Coords)
##
htrsh_pagexml_sort_words () {
  local FN="htrsh_pagexml_sort_words";
  if [ $# != 0 ]; then
    { echo "$FN: Error: Incorrect input arguments";
      echo "Description: Sorts Words from left to right within TextLines in an XML Page file (based ONLY on (xmin+xmax)/2 of the word Coords)";
      echo "Usage: $FN < XMLIN";
    } 1>&2;
    return 1;
  fi

  local XML=$(cat);

  local SORTVALS=( $(
    xmlstarlet sel -t -m '//_:TextLine[_:Word]' -v @id -o " " -v 'count(_:Word)' \
        -m _:Word -o " | " -v @id -o " " -v _:Coords/@points -b -n <( echo "$XML" ) \
      | sed 's|,[0-9]*||g' \
      | awk '
          { printf( "%s %s", $1, $2 );
            mn = 1e9;
            mx = 0;
            id = $4;
            for( n=5; n<=NF; n++ )
              if( $n == "|" ) {
                printf( " %s %g", id, (mn+mx)/2 );
                mn = 1e9;
                mx = 0;
                n ++;
                id = $n;
              }
              else {
                mn = mn > $n ? $n : mn ;
                mx = mx < $n ? $n : mx ;
              }
            printf( " %s %g\n", id, (mn+mx)/2 );
          }' \
      | awk '
          { if( $2 != (NF-2)/2 )
              printf( "parse error at line %s\n", $1 ) > "/dev/stderr";
            else if( $2 != 1 ) {
              for( n=6; n<=NF; n+=2 )
                if( $n <= $(n-2) )
                  break;
              if( n <= NF )
                for( n=3; n<=NF; n+=2 )
                  printf( " -i //_:Word[@id=\"%s\"] -t attr -n sortval -v %s", $n, $(n+1) );
            }
          }'
    ) );

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

  <xsl:template match="//_:TextLine[_:Word/@sortval]">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()[not(self::_:Word) and not(self::_:TextEquiv)]" />
      <xsl:apply-templates select="_:Word">
        <xsl:sort select="@sortval" data-type="number" order="ascending"/>
      </xsl:apply-templates>
      <xsl:apply-templates select="node()[self::_:TextEquiv]" />
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>';

  if [ "${#SORTVALS[@]}" = 0 ]; then
    echo "$XML";
  else
    echo "$XML" \
      | xmlstarlet ed "${SORTVALS[@]}" \
      | xmlstarlet tr <( echo "$XSLT" ) \
      | xmlstarlet ed -d //@sortval;
  fi
}

##
## Function that sorts TextLines within each TextRegion in an XML Page file
## (based ONLY on the first Y coordinate of the baselines)
##
htrsh_pagexml_sort_lines () {
  local FN="htrsh_pagexml_sort_lines";
  if [ $# != 0 ]; then
    { echo "$FN: Error: Incorrect input arguments";
      echo "Description: Sorts TextLines within each TextRegion in an XML Page file (based ONLY on the first Y coordinate of the baselines)";
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
        <xsl:sort select="number(substring-before(substring-after(_:Baseline/@points,&quot;,&quot;),&quot; &quot;))+(number(substring-before(_:Baseline/@points,&quot;,&quot;)) div number($Width))" data-type="number" order="ascending"/>
      </xsl:apply-templates>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>';

  xmlstarlet tr <( echo "$XSLT" );
}

##
## Function that sorts TextRegions in an XML Page file
## (based ONLY on the minimum Y coordinate of the region Coords)
##
# @todo reimplement like the word sort
htrsh_pagexml_sort_regions () {
  local FN="htrsh_pagexml_sort_regions";
  if [ $# != 0 ]; then
    { echo "$FN: Error: Incorrect input arguments";
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

  <xsl:variable name="Width" select="//_:Page/@imageWidth"/>

  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//_:Page">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()[not(self::_:TextRegion)]" />
      <xsl:apply-templates select="_:TextRegion">
        <!--<xsl:sort select="min(for $i in tokenize(replace(_:Coords/@points,'"'\d+,'"','"''"'),'"' '"') return number($i))" data-type="number" order="ascending"/>-->
        <xsl:sort select="min(for $i in tokenize(replace(_:Coords/@points,'"'\d+,'"','"''"'),'"' '"') return number($i))+(min(for $i in tokenize(replace(_:Coords/@points,'"',\d+'"','"''"'),'"' '"') return number($i)) div number($Width))" data-type="number" order="ascending"/>
      </xsl:apply-templates>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>';

  saxonb-xslt -s:- -xsl:<( echo "$XSLT" );
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

  local XSLT3='<?xml version="1.0"?>
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

  <xsl:template match="//_:TextRegion/_:TextLine/_:Word">
    <xsl:variable name="pid" select="../@id"/>
    <xsl:copy>
      <xsl:attribute name="id">
        <xsl:value-of select="concat(../@id,&quot;_w&quot;)"/>
        <xsl:number count="//_:TextRegion/_:TextLine/_:Word"/>
      </xsl:attribute>
      <xsl:apply-templates select="@*[local-name() != '"'id'"'] | node()" />
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>';

  xmlstarlet tr <( echo "$XSLT1" ) \
    | xmlstarlet tr <( echo "$XSLT2" ) \
    | xmlstarlet tr <( echo "$XSLT3" );
}

##
## Function that replaces Coords polygons by bounding boxes
##
htrsh_pagexml_points2bbox () {
  local FN="htrsh_pagexml_points2bbox";
  if [ $# != 0 ]; then
    { echo "$FN: Error: Incorrect input arguments";
      echo "Description: Replaces Coords polygons by bounding boxes";
      echo "Usage: $FN < XMLIN";
    } 1>&2;
    return 1;
  fi

  local XML=$(cat);

  local xmledit=( -d //@dummyattr $(
    xmlstarlet sel -t -m "//$htrsh_xpath_coords" -v ../@id -o " " \
        -v 'translate(@points,","," ")' -n <( echo "$XML" ) \
      | awk '
          { if( NF > 5 ) {
              mn_x = mx_x = $2;
              mn_y = mx_y = $3;
              for( n=4; n<NF; n+=2 ) {
                mn_x = mn_x > $n ? $n : mn_x ;
                mx_x = mx_x < $n ? $n : mx_x ;
                mn_y = mn_y > $(n+1) ? $(n+1) : mn_y ;
                mx_y = mx_y < $(n+1) ? $(n+1) : mx_y ;
              }
              printf( " -u //_:Coords[../@id=\"%s\"]/@points", $1 );
              printf( " -v %s,%s;%s,%s;%s,%s;%s,%s", mn_x,mn_y, mx_x,mn_y, mx_x,mx_y, mn_x,mx_y );
            }
          }'
    ) );

  echo "$XML" \
    | xmlstarlet ed "${xmledit[@]//;/ }";
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

  local xmledit=( ed -d //@dummyattr );
  local id;
  for id in $(xmlstarlet sel -t -m '//_:TextLine/_:Coords[@fpgram]' -v ../@id -n "$XML"); do
    xmledit+=( -d "//_:TextLine[@id='$id']/_:Coords/@points" );
    xmledit+=( -r "//_:TextLine[@id='$id']/_:Coords/@fpgram" -v points );
  done

  xmlstarlet "${xmledit[@]}" "$XML";
}

##
## Function that replaces new line characters in TextEquiv/Unicode with spaces
##
htrsh_pagexml_rm_textequiv_newlines () {
  local FN="htrsh_pagexml_rm_textequiv_newlines";
  if [ $# != 0 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Replaces new line characters in TextEquiv/Unicode with spaces";
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

  <xsl:template match="//_:Unicode">
    <xsl:copy>
      <xsl:value-of select="translate(.,'"'&#10;'"','"' '"')"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>';

  xmlstarlet tr <( echo "$XSLT" );
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
  local $htrsh_infovars;
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
  local RC="0";
  if [ "$htrsh_clean_type" = "line" ]; then
    #convert "$IMFILE" -units PixelsPerCentimeter -density $(echo "$INRES" | sed 's|.* ||') "$OUTDIR/$IMBASE.png";
    #RC="$?";
    cp -p "$XML" "$IMFILE" "$OUTDIR";
    return 0;

  elif [ "$htrsh_imgclean" = "ncsr" ]; then
    EnhanceGray "$IMFILE" "$OUTDIR/$IMBASE.EnhanceGray.$IMEXT" 0 &&
    binarization "$OUTDIR/$IMBASE.EnhanceGray.$IMEXT" "$OUTDIR/$IMBASE.png" 2;
    RC="$?";
    rm -r "$OUTDIR/$IMBASE.EnhanceGray.$IMEXT";

  elif [ "$htrsh_imgclean" = "ncsr_b" ]; then
    binarization "$IMFILE" "$OUTDIR/$IMBASE.png" 2;
    RC="$?";

  elif [ "$htrsh_imgclean" != "prhlt" ]; then
    echo "$FN: error: unexpected preprocessing type: $htrsh_imgclean" 1>&2;
    return 1;

  elif [ "$htrsh_imgtxtenh_regmask" != "yes" ]; then
    imgtxtenh $htrsh_imgtxtenh_opts $INRES "$IMFILE" "$OUTDIR/$IMBASE.png" 2>&1;
    RC="$?";

  else
    local drawreg=( $( xmlstarlet sel -t -m "$htrsh_xpath_regions/$htrsh_xpath_coords" \
                         -o ' -fill gray(' -v '256-position()' -o ')' \
                         -o ' -stroke gray(' -v '256-position()' -o ')' \
                         -o ' -draw polygon_' -v 'translate(@points," ","_")' "$XML"
                         2>/dev/null ) );
    if [ $(echo "$htrsh_xpath_regions" | grep -F '[' | wc -l) != 0 ]; then
      local IXPATH=$(echo "$htrsh_xpath_regions" | sed 's|\[\([^[]*\)]|[not(\1)]|');
      drawreg+=( -fill black -stroke black );
      drawreg+=( $( xmlstarlet sel -t -m "$IXPATH/$htrsh_xpath_coords" \
                      -o ' -draw polygon_' -v 'translate(@points," ","_")' "$XML" \
                      2>/dev/null ) );
    fi

    ### Create mask and enhance selected text regions ###
    convert -size $IMSIZE xc:black +antialias "${drawreg[@]//_/ }" \
        -alpha copy "$IMFILE" +swap -compose copy-opacity -composite miff:- \
      | imgtxtenh $htrsh_imgtxtenh_opts $INRES - "$OUTDIR/$IMBASE.png" 2>&1;
    RC="$?";
  fi

  [ "$RC" != 0 ] &&
    echo "$FN: error: problems enhancing image: $IMFILE" 1>&2 &&
    return 1;

  ### Create new XML with image in current directory and PNG extension ###
  xmlstarlet ed -P -u //@imageFilename -v "$IMBASE.png" "$XML" \
    > "$OUTDIR/$XMLBASE.xml";
}

##
## Function that removes noise from borders of a quadrilateral region defined in an XML Page file
##
# @todo remove evals
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
      echo " -d TMPDIR   Directory for temporal files (def.=$TMPDIR)";
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
  local $htrsh_infovars;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  local IMW=$(echo "$IMSIZE" | sed 's|x.*||');
  local IMH=$(echo "$IMSIZE" | sed 's|.*x||');

  ### Get quadrilaterals ###
  local QUADs=$(xmlstarlet sel -t -m "$htrsh_xpath_regions/$htrsh_xpath_coords" -v @points -n "$XML");
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
  local $htrsh_infovars;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  local XPATH="$htrsh_xpath_regions/$htrsh_xpath_lines/$htrsh_xpath_coords";
  local NUMLINES=$(xmlstarlet sel -t -v "count($XPATH)" "$XML");

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

    xmlstarlet sel -t -m "$XPATH" \
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
htrsh_feats_catregions () {(
  local FN="htrsh_feats_catregions";
  local FEATLST="/dev/null";
  local RMORIG="yes";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Concatenates line features for regions defined in an XML Page file";
      echo "Usage: $FN XML FEATDIR [ Options ]";
      echo "Options:";
      echo " -l FEATLST  Output list of features to file (def.=$FEATLST)";
      echo " -r (yes|no) Whether to remove original features (def.=$RMORIG)";
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
    elif [ "$1" = "-r" ]; then
      RMORIG="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check page and obtain basic info ###
  local $htrsh_infovars;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  [ ! -e "$FEATDIR" ] &&
    echo "$FN: error: features directory not found: $FEATDIR" 1>&2 &&
    return 1;

  local FBASE=$(echo "$FEATDIR/$IMBASE" | sed 's|[\[ ()]|_|g; s|]|_|g;');

  xmlstarlet sel -t -m "$htrsh_xpath_regions/$htrsh_xpath_lines/$htrsh_xpath_coords" \
      -o "$FBASE." -v ../../@id -o "." -v ../@id -o ".fea" -n "$XML" \
    | xargs --no-run-if-empty ls >/dev/null;
  [ "$?" != 0 ] &&
    echo "$FN: error: some line feature files not found" 1>&2 &&
    return 1;

  local IFS=$'\n';
  local id feats f;
  for id in $( xmlstarlet sel -t -m "$htrsh_xpath_regions[$htrsh_xpath_lines/$htrsh_xpath_coords]" -v @id -n "$XML" ); do
    feats=( $( xmlstarlet sel -t -m "//*[@id='$id']/$htrsh_xpath_lines[$htrsh_xpath_coords]" -o "$FBASE.$id." -v @id -o ".fea" -n "$XML" | sed '2,$ s|^|+\n|' ) );

    HCopy "${feats[@]}" "$FBASE.$id.fea";

    echo "$FBASE.$id.fea" >> "$FEATLST";

    feats=( $( xmlstarlet sel -t -m "//*[@id='$id']/$htrsh_xpath_lines[$htrsh_xpath_coords]" -o "$FBASE.$id." -v @id -o ".fea" -n "$XML" ) );

    for f in "${feats[@]}"; do
      echo \
        $( echo "$f" | sed 's|.*\.\([^.][^.]*\)\.fea$|\1|' ) \
        $( HList -h -z "$f" | sed -n '/Num Samples:/{ s|.*Num Samples: *||; s| .*||; p; }' );
    done > "$FBASE.$id.nfea";

    [ "$RMORIG" = "yes" ] &&
      rm "${feats[@]}";
  done

  return 0;
)}

##
## Function that computes a PCA base for a given list of HTK features
##
htrsh_feats_pca () {(
  local FN="htrsh_feats_pca";
  local EXCL="[]";
  local RDIM="";
  local RNDR="no";
  local THREADS="1";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Computes a PCA base for a given list of HTK features";
      echo "Usage: $FN FEATLST OUTMAT [ Options ]";
      echo "Options:";
      echo " -e EXCL     Dimensions to exclude in matlab range format (def.=false)";
      echo " -r RDIM     Return base of RDIM dimensions (def.=all)";
      echo " -R (yes|no) Random rotation (def.=$RNDR)";
      echo " -T THREADS  Threads for parallel processing (def.=$THREADS)";
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
    elif [ "$1" = "-T" ]; then
      THREADS="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if [ ! -e "$FEATLST" ]; then
    echo "$FN: error: feature list not found: $FEATLST" 1>&2;
    return 1;
  elif [ $(wc -l < "$FEATLST") != $(xargs --no-run-if-empty ls < "$FEATLST" | wc -l) ]; then
    echo "$FN: error: some files in list not found: $FEATLST" 1>&2;
    return 1;
  fi

  local htrsh_fastpca="no";
  if [ "$htrsh_fastpca" = "yes" ]; then

    local DIMS=$(HList -h -z $(head -n 1 < "$FEATLST") \
            | sed -n '/^  Num Comps:/{s|^[^:]*: *||;s| .*||;p;}');
    tail -qc +13 $(< "$FEATLST") | swap4bytes | fast_pca -C -e $EXCL -f binary -b 500 -p $DIMS -m "$OUTMAT";

    RC="$?";

  else

  local RC;
  local xEXCL=""; [ "$EXCL" != "[]" ] && xEXCL="se = se + sum(x(:,$EXCL)); x(:,$EXCL) = [];";
  local xxEXCL=""; [ "$EXCL" != "[]" ] && xxEXCL="se = se + cse;";
  local nRDIM="D"; [ "$RDIM" != "" ] && nRDIM="min(D,$RDIM)";

  htrsh_comp_csgma () {
    { local f;
      echo "
        DE = length($EXCL);
        se = zeros(1,DE);
      ";
      for f in $(<"$1"); do
        echo "
          x = readhtk('$f'); $xEXCL
          if ~exist('cN','var')
            cN = size(x,1);
            cmu = sum(x);
            csgma = x'*x;
          else
            cN = cN + size(x,1);
            cmu = cmu + sum(x);
            csgma = csgma + x'*x;
          end
        ";
      done
      echo "
        cse = se;
        save('-z','$2','cN','cmu','csgma','cse');
      ";
    } | octave -q -H;
  }

  run_parallel -T "$THREADS" -n split -l "$FEATLST" htrsh_comp_csgma "{@}" "$OUTMAT.csgma{%}.mat.gz";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems computing PCA" 1>&2 &&
    return 1;

  { local f;
    echo "
      DE = length($EXCL);
      se = zeros(1,DE);
    ";
    for f in "$OUTMAT.csgma"*.mat.gz; do
      echo "
        load('$f'); $xxEXCL
        if ~exist('N','var')
          N = cN;
          mu = cmu;
          sgma = csgma;
        else
          N = N + cN;
          mu = mu + cmu;
          sgma = sgma + csgma;
        end
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

  RC="$?";

  rm "$OUTMAT.csgma"*.mat.gz;

  fi

  [ "$RC" != 0 ] &&
    echo "$FN: error: problems computing PCA" 1>&2;

  return $RC;
)}

##
## Function that projects a list of features for a given base
##
htrsh_feats_project () {(
  local FN="htrsh_feats_project";
  local THREADS="1";
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
  shift 3;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-T" ]; then
      THREADS="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

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

  feats_project () {
    { echo "load('$PBASE');"
      local f ff;
      for f in $(<"$1"); do
        ff=$(echo "$f" | sed "s|.*/|$OUTDIR/|");
        echo "
          [x,FP,DT,TC] = readhtk('$f');
          x = (x-repmat(mu,size(x,1),1))*B;
          writehtk('$ff',x,FP,TC);
          ";
      done
    } | octave -q -H;
  }

  if [ "$THREADS" = 1 ]; then
    feats_project "$FEATLST";
  else
    run_parallel -T $THREADS -n balance -l "$FEATLST" feats_project '{@}';
  fi

  [ "$?" != 0 ] &&
    echo "$FN: error: problems projecting features" 1>&2 &&
    return 1;

  return 0;
)}

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

  sed 's|^\([^/]*\)\.fea$|\1 \1.fea|;
       s|^\(.*/\)\([^/]*\)\.fea$|\2 \1\2.fea|;' \
    | copy-feats --htk-in scp:- ark,scp:$1.ark,$1.scp;

  return $?;
}

##
## Function that extracts line features from an image given its XML Page file
##
htrsh_pageimg_extract_linefeats () {
  local FN="htrsh_pageimg_extract_linefeats";
  local OUTDIR=".";
  local FEATLST="/dev/null";
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
  local $htrsh_infovars;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  ### Extract lines from line coordinates ###
  local LINEIMGS=$(htrsh_pageimg_extract_lines "$XML" -d "$OUTDIR");
  ( [ "$?" != 0 ] || [ "$LINEIMGS" = "" ] ) && return 1;

  local xmledit=( ed );
  local FEATS="";

  ### Process each line ###
  local oklines="0";
  local n;
  for n in $(seq 1 $(echo "$LINEIMGS" | wc -l)); do
    local ff=$(echo "$LINEIMGS" | sed -n $n'{s|\.png$||;p;}');
    local id=$(echo "$ff" | sed 's|.*\.||');

    echo "$FN: processing line image ${ff}.png";

    ### Clean and trim line image ###
    if [ "$htrsh_clean_type" = "line" ]; then
      imgtxtenh $htrsh_imgtxtenh_opts -a ${ff}.png miff:- \
        | imglineclean $htrsh_imglineclean_opts - ${ff}_clean.png;
    else
      imglineclean $htrsh_imglineclean_opts ${ff}.png ${ff}_clean.png;
    fi 2>&1;
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
      slope=$(convert ${ff}_clean.png +repage -flatten \
               -deskew 40% -print '%[deskew:angle]\n' \
               -trim +repage ${ff}_deslope.png);
      #slope=$(imageSlope -i ${ff}_clean.png -o ${ff}_deslope.png -v 1 -s 10000 2>&1 \
      #         | sed -n '/slope medio:/{s|.* ||;p;}');

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
      [ $(identify -format "%wx%h" ${ff}_affine.png) = "1x1" ] &&
        mn=$(convert ${ff}_clean.png +repage -flatten \
               -virtual-pixel white +distort AffineProjection ${affine} \
               -shave 1x1 -format %X,%Y -write info: \
               +repage ${ff}_affine.png);
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
    #xmledit+=( -i "//*[@id='$id']/_:Coords" -t attr -n bbox -v "$bbox" );
    #xmledit+=( -i "//*[@id='$id']/_:Coords" -t attr -n slope -v "$slope" );
    #[ "$htrsh_feat_deslant" = "yes" ] &&
    #xmledit+=( -i "//*[@id='$id']/_:Coords" -t attr -n slant -v "$slant" );
    xmledit+=( -i "//*[@id='$id']/_:Coords" -t attr -n fpgram -v "$fpgram" );

    ### Compute detailed contours if requested ###
    if [ "$htrsh_feat_contour" = "yes" ]; then
      local pts=$(imgccomp -V1 -NJS -A 0.5 -D $htrsh_feat_dilradi -R 5,2,2,2 ${ff}_clean.png);
      [ "$pts" = "" ] && pts="$fpgram";
      xmledit+=( -i "//*[@id='$id']/_:Coords" -t attr -n fcontour -v "$pts" );
    fi 2>&1;

    local FEATOP="";
    if [ "$htrsh_feat_normxheight" != "" ]; then
      FEATOP=$(xmlstarlet sel -t -v "//*[@id='$id']/@custom" "$XML" 2>/dev/null \
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
    #rm "${ff}_clean.png";
    [ "$htrsh_keeptmp" -lt 1 ] &&
      rm -f "${ff}.png" "${ff}_fea.png";
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
  xmlstarlet "${xmledit[@]}" "$XML" > "$XMLOUT";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems generating XML file: $XMLOUT" 1>&2 &&
    return 1;

  if [ "$htrsh_feat_contour" = "yes" ] && [ "$REPLC" = "yes" ]; then
    xmledit=( ed --inplace );
    local id;
    for id in $(xmlstarlet sel -t -m '//*/_:Coords[@fcontour]' -v ../@id -n "$XMLOUT"); do
      xmledit+=( -d "//*[@id='${id}']/_:Coords/@points" );
      xmledit+=( -r "//*[@id='${id}']/_:Coords/@fcontour" -v points );
    done
    xmlstarlet "${xmledit[@]}" "$XMLOUT";
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
      echo " -d OUTDIR       Directory for output models and temporal files (def.=$OUTDIR)";
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

  local ORDEROPTS=( -order $ORDER );
  local n;
  for n in $(seq 1 $ORDER); do
    ORDEROPTS+=( -ukndiscount$n );
  done

  local GAWK_CREATE_DIC='
    BEGIN {
      FS="\t";
      while( (getline line<SPECIAL) > 0 )
        if( line != "" ) {
          n = split(line,sline," ");
          c = substr( sline[1], 1, 1 );
          SCHAR[c] = "";
          NSPECIAL++;
          SWORD[NSPECIAL] = sline[1];
          SMARK[NSPECIAL] = n == 1 ? sline[1] : sline[2] ;
        }
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
          utxt = variant_models[canonic][variant];
          N = split( utxt, txt, "" );
          cprev = "@";
          for( n=1; n<=N; n++ ) {
            printf( n==1 ? "" : " " );
            if( txt[n] in SCHAR ) {
              for( m=1; m<=NSPECIAL; m++ ) {
                w = SWORD[m];
                if( w == substr(utxt,n,length(w)) ) {
                  if( TYPE == "overlap" )
                    printf( "%s%s ", cprev, SMARK[m] );
                  cprev = SMARK[m];
                  printf( "%s", SMARK[m] );
                  n += length(w)-1;
                  break;
                }
              }
              if( m <= NSPECIAL )
                continue;
            }
            if( TYPE == "overlap" )
              printf( "%s%s ", cprev, txt[n] );
            cprev = txt[n];
            printf( "%s", txt[n] );
          }
          if( TYPE == "overlap" )
            printf( " %s@", cprev );
          printf( " @\n" );
        }
      }
    }';

  ### Tokenize training text ###
  cat "$TXT" \
    | $TOKENIZER \
    > "$OUTDIR/text_tokenized.txt";

  ### Create dictionary ###
  paste \
      <( cat "$OUTDIR/text_tokenized.txt" \
           | $CANONIZER \
           | tee "$OUTDIR/text_canonized.txt" \
           | tr ' ' '\n' ) \
      <( cat "$OUTDIR/text_tokenized.txt" \
           | tr ' ' '\n' ) \
      <( cat "$OUTDIR/text_tokenized.txt" \
           | $DIPLOMATIZER \
           | tr ' ' '\n' ) \
    | gawk -v TYPE="$htrsh_hmm_type" -v SPECIAL=<( echo "$htrsh_special_chars" ) "$GAWK_CREATE_DIC" \
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
      -lm - "${ORDEROPTS[@]}" \
    | sed 's|\(["\x27]\)|\\\1|g' \
    > "$OUTDIR/langmodel_${ORDER}-gram.arpa";

  HBuild -n "$OUTDIR/langmodel_${ORDER}-gram.arpa" -s "<s>" "</s>" \
    "$OUTDIR/dictionary.txt" "$OUTDIR/langmodel_${ORDER}-gram.lat";

  [ "$htrsh_keeptmp" -lt 1 ] &&
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
  local NUMELEM="balance";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Trains HMMs for a given feature list and mlf";
      echo "Usage: $FN FEATLST MLF [ Options ]";
      echo "Options:";
      echo " -d OUTDIR    Directory for output models and temporal files (def.=$OUTDIR)";
      echo " -c CODES     Train discrete model with given codebook size (def.=false)";
      echo " -P PROTO     Use PROTO as initialization prototype (def.=false)";
      echo " -k (yes|no)  Whether to keep models per iteration, including initialization (def.=$KEEPITERS)";
      echo " -r (yes|no)  Whether to resume previous training, looks for models per iteration (def.=$RESUME)";
      echo " -R (yes|no)  Whether to randomize initialization prototype (def.=$RAND)";
      echo " -T THREADS   Threads for parallel processing (def.=$THREADS)";
      echo " -n NUMELEM   Elements per instance for parallel (see run_parallel) (def.=$NUMELEM)";
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
      THREADS="$2";
    elif [ "$1" = "-n" ]; then
      NUMELEM="$2";
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

      htrsh_hmm_proto "$DIMS" 1 | gzip > "$OUTDIR/proto";
      HCompV $htrsh_HTK_HCompV_opts -C <( echo "$htrsh_HTK_config" ) \
        -S "$FEATLST" -M "$OUTDIR" "$OUTDIR/proto" 1>&2;

      local GLOBAL=$(< "$OUTDIR/vFloors");
      local MEAN=$(gzip -dc "$OUTDIR/proto" | sed -n '/<MEAN>/{N;s|.*\n||;p;q;}');
      local VARIANCE=$(gzip -dc "$OUTDIR/proto" | sed -n '/<VARIANCE>/{N;s|.*\n||;N;p;q;}');

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
          run_parallel -T $THREADS -n $NUMELEM -l "$FEATLST" \
            HERest $htrsh_HTK_HERest_opts -C <( echo "$htrsh_HTK_config" ) -p '{#}' \
            -S '{@}' -I "$MLF" -H "$OUTDIR/Macros_hmm.gz" -M "$OUTDIR" <( echo "$HMMLST" ) 1>&2;
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

        local TE=$(($(date +%s%N)/1000000)); echo "$FN: time g=$g i=$i: $((TE-TS)) ms" 1>&2; TS="$TE";

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
  local CMD=( "$2" );
  shift 2;

  local TMP="${TMPDIR:-.}";
  TMP=$(mktemp -d --tmpdir="$TMP" ${FN}_XXXXX);
  [ ! -d "$TMP" ] &&
    echo "$FN: error: failed to create temporal directory" 1>&2 &&
    return 1;

  local FEATLST="";
  local MLF="";
  while [ $# -gt 0 ]; do
    CMD+=( "$1" );
    if [ "$1" = "-S" ]; then
      FEATLST="$2";
      CMD+=( "{@}" );
      shift 1;
    elif [ "$1" = "-i" ]; then
      MLF="$2";
      CMD+=( "$TMP/mlf_{#}" );
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
    | run_parallel -T $THREADS -n balance -l - -d "$TMP" "${CMD[@]}" 1>&2;
  [ "$?" != 0 ] &&
    echo "$FN: error: problems executing $CMD ($TMP)" 1>&2 &&
    return 1;

  [ "$MLF" != "" ] &&
    { echo "#!MLF!#";
      sed '/^#!MLF!#/d' "$TMP/mlf_"*;
    } > "$MLF";

  [ "$htrsh_keeptmp" -lt 1 ] &&
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
          $3 = gensub( /^\x27(.*)\x27$/, "\\1", 1, $3 );
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
# @todo should modify this so that the replacement is only in TextEquiv/Unicode, not all the XML
htrsh_fix_rec_names () {
  local FN="htrsh_fix_rec_names";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Replaces special HMM model names with corresponding characters";
      echo "Usage: $FN XMLIN";
    } 1>&2;
    return 1;
  fi

  local SED_REP="s|@| |g;"$(
    echo "$htrsh_special_chars" \
      | sed '
          s/^\([^ ]*\) \([^ ]*\)/s|\2|\1|g;/;
          s/&/\\\&amp;/g;
          s/</\\\&lt;/g;
          s/>/\\\&gt;/g;' );

  sed -i "$SED_REP" "$1";

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
          $3 = gensub( /\\"/, "\"", "g", gensub( /^"(.+)"$/, "\\1", 1, $3 ) );
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

  ### Check XML file ###
  local $htrsh_infovars;
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
                id = gensub(/.*\.([^.]+)\.rec"$/, "\\1", 1, $0 );
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

  local fpgram=( xmlstarlet sel -t );
  local id;
  for id in $ids; do
    fpgram+=( -o " " -v "//*[@id='$id']/_:Coords/@fpgram" -o " ;" );
  done

  local acoords=$(
    echo "
      fpgram = [ "$( "${fpgram[@]}" "$XML" )" ];
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

  ( [ "$htrsh_align_contour" = "yes" ] || [ "$htrsh_align_isect" = "yes" ] ) &&
    local size=$(xmlstarlet sel -t -v //@imageWidth -o x -v //@imageHeight "$XML");

  local n=0;
  for id in $ids; do
    n=$((n+1));
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): alignments for line $n (id=$id) ..." 1>&2;

    local xmledit=( -d "//*[@id='$id']/_:Word" );

    local LIMG LGEO contour;
    if [ "$htrsh_align_contour" = "yes" ]; then
      LIMG="$XMLDIR/$IMBASE."$(xmlstarlet sel -t -v "//*[@id='$id']/../@id" "$XML")".${id}_clean.png";
      LGEO=( $(identify -format "%w %h %X %Y %x %U" "$LIMG" | sed 's|+||g') );
    elif [ "$htrsh_align_isect" = "yes" ]; then
      contour=$(xmlstarlet sel -t -v '//*[@id="'$id'"]/_:Coords/@points' "$XML");
    fi

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

      if [ "$htrsh_align_contour" = "yes" ]; then
        local cpts=$( echo $pts \
                 | awk -F'[, ]' -v oX=${LGEO[2]} -v oY=${LGEO[3]} '
                     { for( n=1; n<NF; n+=2 )
                         printf( " %s,%s", $n-oX, $(n+1)-oY );
                     }' );
        cpts=$( convert -fill black -stroke black -size ${LGEO[0]}x${LGEO[1]} \
                    xc:white +antialias -draw "polygon$cpts" "$LIMG" \
                    -compose lighten -composite -page $size+${LGEO[2]}+${LGEO[3]} \
                    -units ${LGEO[5]} -density ${LGEO[4]} miff:- \
                  | imgccomp -V0 -NJS -A 0.1 -D $htrsh_align_dilradi -R 2,2,2,2 - 2>/dev/null );
        [ "$cpts" != "" ] && pts="$cpts";

      elif [ "$htrsh_align_isect" = "yes" ]; then
        local AWK_ISECT='
          BEGIN {
            printf( "convert -fill white -stroke white +antialias" );
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
            printf( " ( -size %dx%d xc:black -draw polygon", w, h );
            for( n=1; n<=NF; n+=2 )
              printf( "_%d,%d", $n-mn_x, $(n+1)-mn_y );
            printf( " )" );
          }
          END {
            printf( " -compose darken -composite -page %s+%d+%d miff:-", sz, mn_x, mn_y );
          }';
        local polydraw=( $(
          { echo "$pts";
            echo "$contour";
          } | awk -F'[ ,]' -v sz=$size "$AWK_ISECT" ) );
        pts=$( "${polydraw[@]//_/ }" | imgccomp -V0 -JS - );
      fi
      local wpts="$pts";

      #TE=$(($(date +%s%N)/1000000)); echo "time 4: $((TE-TS)) ms" 1>&2; TS="$TE";

      xmledit+=( -s "//*[@id='$id']" -t elem -n TMPNODE );
      xmledit+=( -i //TMPNODE -t attr -n id -v "${id}_w${ww}" );
      xmledit+=( -s //TMPNODE -t elem -n Coords );
      xmledit+=( -i //TMPNODE/Coords -t attr -n points -v "$pts" );
      xmledit+=( -r //TMPNODE -v Word );

      ### Character level alignments ###
      if [ "$htrsh_align_chars" = "yes" ]; then
        local g=1;
        local c;
        for c in $(seq $pS $pE); do
          local gg=$(printf %.2d $g);
          local pts=$(echo "$coords" | sed -n "${c}p");
          if [ "$htrsh_align_isect" = "yes" ]; then
            local polydraw=( $(
              { echo "$pts";
                echo "$wpts";
              } | awk -F'[ ,]' -v sz=$size "$AWK_ISECT" ) );
            pts=$( "${polydraw[@]//_/ }" | imgccomp -V0 -JS - );
            # @todo character polygons overlap slightly, possible solution: reduce width of parallelograms by 1 pixel in each side
          fi

          xmledit+=( -s "//*[@id='${id}_w${ww}']" -t elem -n TMPNODE );
          xmledit+=( -i //TMPNODE -t attr -n id -v "${id}_w${ww}_g${gg}" );
          xmledit+=( -s //TMPNODE -t elem -n Coords );
          xmledit+=( -i //TMPNODE/Coords -t attr -n points -v "$pts" );
          if [ "$htrsh_align_addtext" = "yes" ]; then
            local text=$(echo "$align" | sed -n "$c{s|.* ||;p;}" | tr -d '\n');
            xmledit+=( -s //TMPNODE -t elem -n TextEquiv );
            xmledit+=( -s //TMPNODE/TextEquiv -t elem -n Unicode -v "$text" );
          fi
          xmledit+=( -r //TMPNODE -v Glyph );

          g=$((g+1));
        done
      fi

      #TE=$(($(date +%s%N)/1000000)); echo "time 5: $((TE-TS)) ms" 1>&2; TS="$TE";

      if [ "$htrsh_align_addtext" = "yes" ]; then
        local text=$(echo "$align" | sed -n "$pS,$pE{s|.* ||;p;}" | tr -d '\n');
        xmledit+=( -s "//*[@id='${id}_w${ww}']" -t elem -n TextEquiv );
        xmledit+=( -s "//*[@id='${id}_w${ww}']/TextEquiv" -t elem -n Unicode -v "$text" );
        #TE=$(($(date +%s%N)/1000000)); echo "time 6: $((TE-TS)) ms" 1>&2; TS="$TE";
      fi
    done

    xmledit+=( -m "//*[@id='$id']/_:TextEquiv" "//*[@id='$id']" );

    xmlstarlet ed --inplace "${xmledit[@]}" "$XML";
    [ "$?" != 0 ] &&
      echo "$FN: error: problems creating XML file: $XMLOUT" 1>&2 &&
      return 1;
  done

  return 0;
}

##
## Function that does a forced alignment at a line level for a given XML Page, feature list and model
##
htrsh_pageimg_forcealign_lines () {
  local FN="htrsh_pageimg_forcealign_lines";
  local TMPDIR=".";
  if [ $# -lt 3 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Does a forced alignment at a line level for a given XML Page, feature list and model";
      echo "Usage: $FN XML FEATDIR MODEL [ Options ]";
      echo "Options:";
      echo " -d TMPDIR    Directory for temporal files (def.=$TMPDIR)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local XML="$1";
  local FEATDIR="$2";
  local MODEL="$3";
  shift 3;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      TMPDIR="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if [ ! -e "$XML" ]; then
    echo "$FN: error: Page XML file not found: $XML" 1>&2;
    return 1;
  elif [ ! -e "$FEATDIR" ]; then
    echo "$FN: error: features directory not found: $FEATDIR" 1>&2;
    return 1;
  elif [ ! -e "$MODEL" ]; then
    echo "$FN: error: model file not found: $MODEL" 1>&2;
    return 1;
  fi

  ### Check XML file and image ###
  local $htrsh_infovars;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;
  local B=$(echo "$XMLBASE" | sed 's|[\[ ()]|_|g; s|]|_|g;');
  echo "$FN: aligning $B" 1>&2;

  ### Check feature files ###
  local pIFS="$IFS";
  local IFS=$'\n';
  local FBASE="$FEATDIR/"$(echo "$IMFILE" | sed 's|.*/||; s|\.[^.]*$||;');
  local FEATLST=( $( xmlstarlet sel -t -m "$htrsh_xpath_regions/$htrsh_xpath_lines[$htrsh_xpath_coords]" -o "$FBASE." -v ../@id -o . -v @id -o ".fea" -n "$XML" ) );
  IFS="$pIFS";

  ls "${FEATLST[@]}" >/dev/null;
  [ "$?" != 0 ] &&
    echo "$FN: error: some .fea files not found" 1>&2 &&
    return 1;

  ### Create MLF from XML ###
  { echo '#!MLF!#'; htrsh_pagexml_textequiv "$XML" -f mlf-chars; } > "$TMPDIR/$B.mlf";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating MLF file: $XML" 1>&2 &&
    return 1;

  ### Create auxiliary files: HMM list and dictionary ###
  local HMMLST=$(gzip -dc "$MODEL" | sed -n '/^~h "/{ s|^~h "||; s|"$||; p; }');
  local DIC=$(echo "$HMMLST" | awk '{printf("\"%s\" [%s] 1.0 %s\n",$1,$1,$1)}');

  ### Do forced alignment with HVite ###
  printf "%s\n" "${FEATLST[@]}" > "$TMPDIR/$B.lst";
  HVite $htrsh_HTK_HVite_opts -C <( echo "$htrsh_HTK_config" ) -H "$MODEL" -S "$TMPDIR/$B.lst" -m -I "$TMPDIR/$B.mlf" -i "$TMPDIR/${B}_aligned.mlf" <( echo "$DIC" ) <( echo "$HMMLST" );
  [ "$?" != 0 ] &&
    echo "$FN: error: problems aligning with HVite: $XML" 1>&2 &&
    return 1;

  ### Insert alignment information in XML ###
  htrsh_pagexml_insertalign_lines "$XML" "$TMPDIR/${B}_aligned.mlf";
  [ "$?" != 0 ] &&
    return 1;

  local missing=$(
          { sed 's|.*\.\([^.]\+\)\.fea$|\1|' "$TMPDIR/$B.lst";
            sed -n '
              /\/'"$IMBASE"'\.[^.]\+\.[^.]\+\.rec"$/ {
                s|.*\.\([^.]\+\)\.rec"$|\1|;
                p;
              }' "$TMPDIR/${B}_aligned.mlf";
          } | sort | uniq -u );

  if [ "$missing" != "" ]; then
    echo "$FN: error: unaligned lines: $B $(echo $missing)" 1>&2;
    local xmledit=( ed --inplace );
    local id;
    for id in $missing; do
      local line=$(htrsh_xpath_lines="*[@id='$id']" htrsh_pagexml_textequiv "$XML");
      for w in $(seq 1 $(echo "$line" | awk '{print NF}')); do
        local ww=$(echo "$line" | awk '{printf("%s",$'$w')}');
        xmledit+=( -s "//*[@id='$id']" -t elem -n TMPNODE );
        xmledit+=( -i //TMPNODE -t attr -n id -v ${id}_w$(printf %.2d $w) );
        xmledit+=( -s //TMPNODE -t elem -n Coords );
        xmledit+=( -i //TMPNODE/Coords -t attr -n points -v "0,0 0,0" );
        xmledit+=( -s //TMPNODE -t elem -n TextEquiv );
        xmledit+=( -s //TMPNODE/TextEquiv -t elem -n Unicode -v "$ww" );
        xmledit+=( -r //TMPNODE -v Word );
      done
      xmledit+=( -m "//*[@id='$id']/_:TextEquiv" "//*[@id='$id']" );
    done
    xmlstarlet "${xmledit[@]}" "$XML";
  fi

  htrsh_fix_rec_names "$XML"; # @todo move this inside htrsh_pagexml_insertalign_lines?

  [ "$htrsh_keeptmp" -lt 1 ] &&
    rm -f "$TMPDIR/$B.mlf" "$TMPDIR/$B.lst" "$TMPDIR/${B}_aligned.mlf";

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
      echo " -d TMPDIR    Directory for temporal files (def.=$TMPDIR)";
      echo " -i INRES     Input image resolution in ppc (def.=use image metadata)";
      echo " -m MODEL     Use given model for aligning (def.=train model for page)";
      echo " -b PBASE     Project features using given base (def.=false)";
      echo " -e (yes|no)  Whether to enhance the image using imgtxtenh (def.=$ENHIMG)";
      echo " -p (yes|no)  Whether to compute PCA for image and project features (def.=$DOPCA)";
      echo " -t (yes|no)  Whether to keep temporal directory and files (def.=$KEEPTMP)";
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
    echo -n "$FN: temporal directory ($TMPDIR) already exists, current contents will be deleted, continue? " 1>&2;
    local RMTMP="";
    read -n 1 RMTMP;
    [ "${RMTMP:0:1}" != "y" ] &&
      printf "\n$FN: aborting ...\n" 1>&2 &&
      return 1;
    rm -r "$TMPDIR";
    echo 1>&2;
  fi

  ### Check page ###
  local $htrsh_infovars;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  local RCNT=$(xmlstarlet sel -t -v "count($htrsh_xpath_regions/$htrsh_xpath_textequiv)" "$XML");
  #local RCNT="0";
  local LCNT=$(xmlstarlet sel -t -v "count($htrsh_xpath_regions/$htrsh_xpath_lines/$htrsh_xpath_textequiv)" "$XML");
  [ "$RCNT" = 0 ] && [ "$LCNT" = 0 ] &&
    echo "$FN: error: no TextEquiv/Unicode nodes for processing: $XML" 1>&2 &&
    return 1;

  local WGCNT=$(xmlstarlet sel -t -v 'count(//_:Word)' -o ' ' -v 'count(//_:Glyph)' "$XML");
  [ "$WGCNT" != "0 0" ] &&
    echo "$FN: warning: input already contains Word and/or Glyph information: $XML" 1>&2;

  local AREG=( -s lines ); [ "$LCNT" = 0 ] && AREG[1]="regions";

  local B=$(echo "$XMLBASE" | sed 's|[\[ ()]|_|g; s|]|_|g;');

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): processing page: $XML";

  mkdir -p "$TMPDIR/proc";
  cp -p "$XML" "$IMFILE" "$TMPDIR/proc";
  sed 's|\(imageFilename="\)[^"/]*/|\1|' -i "$TMPDIR/proc/$XMLBASE.xml";

  ### Generate contours from baselines ###
  if [ $(xmlstarlet sel -t -v \
           "count($htrsh_xpath_regions/$htrsh_xpath_lines/_:Baseline)" \
           "$XML") -gt 0 ] && (
       [ "$htrsh_align_prefer_baselines" = "yes" ] ||
       [ $(xmlstarlet sel -t -v \
             "count($htrsh_xpath_regions/$htrsh_xpath_lines/$htrsh_xpath_coords)" \
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
  htrsh_xpath_lines="_:TextLine[$htrsh_xpath_textequiv]" \
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
  fi #| sed '/^$/d';
  if [ "$PBASE" != "" ]; then
    [ ! -e "$PBASE" ] &&
      echo "$FN: error: projection base file not found: $PBASE" 1>&2 &&
      return 1;
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): projecting features ...";
    htrsh_feats_project "$TMPDIR/${B}_feats.lst" "$PBASE" "$TMPDIR";
    [ "$?" != 0 ] && return 1;
  fi | sed '/^$/d';

  [ "${AREG[1]}" = "regions" ] &&
    htrsh_feats_catregions "$TMPDIR/${XMLBASE}_feats.xml" "$TMPDIR" -l $TMPDIR/${B}_feats.lst;

  ### Train HMMs model for this single page ###
  if [ "$MODEL" = "" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): training model for page ...";
    { echo '#!MLF!#';
      htrsh_pagexml_textequiv "$TMPDIR/${XMLBASE}_feats.xml" -f mlf-chars "${AREG[@]}" -F "$FILTER";
    } > "$TMPDIR/${B}_page.mlf";
    [ "$?" != 0 ] && return 1;
    MODEL=$(
      htrsh_hmm_train "$TMPDIR/${B}_feats.lst" "$TMPDIR/${B}_page.mlf" -d "$TMPDIR" -k no \
        2> "$TMPDIR/${XMLBASE}_hmmtrain.log"
      );
    [ "$?" != 0 ] &&
      echo "$FN: error: problems training model, more info might be in file $TMPDIR/${XMLBASE}_hmmtrain.log" 1>&2 &&
      return 1;

  ### Check that given model has all characters, otherwise add protos for these ###
  else
    local CHARCHECK=$(
            htrsh_pagexml_textequiv "$TMPDIR/${XMLBASE}_feats.xml" \
                -f mlf-chars "${AREG[@]}" -F "$FILTER" \
              | sed '/^"\*\/.*"$/d; /^\.$/d; s|^"\(.*\)"|\1|;' \
              | sort -u);
    CHARCHECK=$(
      gzip -dc "$MODEL" \
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

      local MEAN=$(gzip -dc "$TMPDIR/proto" | sed -n '/<MEAN>/{N;s|.*\n||;p;q;}');
      local VARIANCE=$(gzip -dc "$TMPDIR/proto" | sed -n '/<VARIANCE>/{N;s|.*\n||;N;p;q;}');
      local NEWMODEL="$TMPDIR"/$(echo "$MODEL" | sed 's|.*/||');

      { gzip -dc "$MODEL";
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
  cp "$TMPDIR/${XMLBASE}_feats.xml" "$TMPDIR/${XMLBASE}_align.xml";
  local forcealign="htrsh_pageimg_forcealign_lines";
  [ "${AREG[1]}" = "regions" ] &&
    forcealign="htrsh_pageimg_forcealign_regions";
  $forcealign "$TMPDIR/${XMLBASE}_align.xml" "$TMPDIR" "$MODEL" -d "$TMPDIR" \
    > "$TMPDIR/${XMLBASE}_forcealign.log";
  [ "$?" != 0 ] &&
    echo "$FN: error: more info might be in file $TMPDIR/${XMLBASE}_forcealign.log" 1>&2 &&
    return 1;
  mv "$TMPDIR/${XMLBASE}_align.xml" "$XMLOUT";

  [ "$KEEPTMP" != "yes" ] && rm -r "$TMPDIR";

  local I=$(xmlstarlet sel -t -v //@imageFilename "$XML");
  local xmledit=( -u //@imageFilename -v "$I" );
  [ "$KEEPAUX" != "yes" ] && xmledit+=( -d //@fpgram -d //@fcontour );

  xmlstarlet ed --inplace ${xmledit[@]} "$XMLOUT";

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
