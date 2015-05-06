#!/bin/bash

##
## Collection of shell functions for Handwritten Text Recognition.
##
## @version $Revision$$Date::             $
## @author Mauricio Villegas <mauvilsa@upv.es>
## @copyright Copyright(c) 2014 to the present, Mauricio Villegas (UPV)
##


[ "$(type -t htrsh_version)" = "function" ] &&
  echo "htrsh.inc.sh: warning: library already loaded, to reload first use htrsh_unload" 1>&2 &&
  return 0;

#-----------------------#
# Default configuration #
#-----------------------#

htrsh_valschema="yes";
#htrsh_pagexsd="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15/pagecontent.xsd";
htrsh_pagexsd="http://mvillegas.info/xsd/2013-07-15/pagecontent.xsd";

htrsh_keeptmp="0";

htrsh_text_translit="no";

htrsh_imgtxtenh_opts="-r 0.16 -w 20 -k 0.1"; # Options for imgtxtenh tool
htrsh_imglineclean_opts="-m 99%";            # Options for imglineclean tool

htrsh_feat_padding="0.5"; # Left and right white padding in mm for line images
htrsh_feat_contour="yes"; # Whether to compute connected components contours
htrsh_feat_dilradi="0.5"; # Dilation radius in mm for contours

htrsh_feat="dotmatrix";    # Type of features to extract
htrsh_dotmatrix_shift="2"; # Sliding window shift in px, should change this to mm
htrsh_dotmatrix_win="20";  # Sliding window width in px, should change this to mm
htrsh_dotmatrix_W="8";     # Width of normalized frame in px, should change this to mm
htrsh_dotmatrix_H="32";    # Height of normalized frame in px, should change this to mm
htrsh_dotmatrix_mom="yes"; # Whether to add moments to features

htrsh_hmm_states="6"; # Number of HMM states (excluding special initial and final)
htrsh_hmm_nummix="4"; # Number of Gaussian mixture components
htrsh_hmm_iter="4";   # Number of training iterations

htrsh_HTK_HERest_opts="-m 2";      # Options for HERest tool
htrsh_HTK_HCompV_opts="-f 0.1 -m"; # Options for HCompV tool
htrsh_HTK_HHEd_opts="";            # Options for HHEd tool
htrsh_HTK_HVite_opts="";           # Options for HVite tool

#htrsh_HTK_HERest_opts="-A -T 1 -m 3";
#htrsh_HTK_HCompV_opts="-A -T 1 -f 0.1 -m";
#htrsh_HTK_HHEd_opts="-A";
#htrsh_HTK_HVite_opts="-A -T 1";

htrsh_baseHTKcfg='
HPARMFILTER    = "gzip -d -c $.gz"
HPARMOFILTER   = "gzip -c > $.gz"
HMMDEFFILTER   = "gzip -d -c $"
HMMDEFOFILTER  = "gzip -c > $"
';


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
  return 0;
}

##
## Function that checks that all required commands are available
##
htrsh_check_req () {
  local FN="htrsh_check_req";
  local cmd;
  for cmd in xmlstarlet convert octave HVite pfl2htk imgtxtenh imglineclean imgpageborder imgccomp imageSlant realpath page_format_generate_contour; do
    local c=$(which $cmd);
    [ ! -e "$c" ] &&
      echo "$FN: WARNING: unable to find command: $cmd" 1>&2;
  done

  [ $(octave -q --eval 'which readhtk' | wc -l) = 0 ] &&
    echo "$FN: WARNING: unable to find octave command: readhtk" 1>&2;

  htrsh_version;
  for cmd in imgtxtenh imglineclean imgpageborder imgccomp; do
    $cmd --version;
  done
  { printf "xmlstarlet "; xmlstarlet --version | head -n 1;
    convert --version | sed -n '1{ s|^Version: ||; p; }';
    octave --version | head -n 1;
    HVite -V | grep HVite | cat;
  } 1>&2;

  return 0;
}


#--------------------------------#
# XML Page manipulation fuctions #
#--------------------------------#

##
## Function that prints to stdout an MLF created from an XML PAGE file
##
# @todo this needs to be improved a lot
htrsh_page_to_mlf () {
  local FN="htrsh_page_to_mlf";
  local XPATH='//_:TextRegion[@type="paragraph"]';
  local REGSRC="no";
  if [ $# -lt 1 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLFILE [ OPTIONS ]";
      echo "Options:";
      echo " -x XPATH     XPath for region selection (def.=$XPATH)";
      echo " -r (yes|no)  Whether to get TextEquiv from regions instead of lines (def.=$REGSRC)";
    } 1>&2;
    return 1;
  fi

  local XML="$1";
  shift;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-x" ]; then
      XPATH="$2";
    elif [ "$1" = "-r" ]; then
      REGSRC="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check page ###
  htrsh_pageimg_info "$XML" noinfo;
  [ "$?" != 0 ] && return 1;

  local TAB=$(printf "\t");
  local PG=$(xmlstarlet sel -t -v //@imageFilename "$XML" | sed 's|.*/||; s|\.[^.]*$||;');

  local IDop;
  if [ "$REGSRC" = "yes" ]; then
    XPATH="$XPATH/_:TextEquiv/_:Unicode";
    IDop="-o $PG. -v ../../@id";
  else
    XPATH="$XPATH/_:TextLine/_:TextEquiv/_:Unicode";
    IDop="-o $PG. -v ../../../@id -o . -v ../../@id";
  fi

  [ $(xmlstarlet sel -t -v "count($XPATH)" "$XML") = 0 ] &&
    echo "$FN: error: zero nodes match xpath $XPATH on file: $XML" 1>&2 &&
    return 1;

  echo '#!MLF!#';
  if [ "$htrsh_text_translit" != "yes" ]; then
    cat "$XML" | tr '\t' ' ' \
      | xmlstarlet sel -T -B -E utf-8 -t -m "$XPATH" \
          $IDop -o "$TAB" -v . -n;
  else
    cat "$XML" | tr '\t' ' ' \
      | xmlstarlet sel -T -B -E utf-8 -t -m "$XPATH" \
          $IDop -o "$TAB" -v . -n \
      | iconv -f utf8 -t ascii//TRANSLIT;
  fi \
    | sed '
        #s|\xc2\xad|-|g;
        s|^  *||;
        s|  *$||;
        s|   *| |g;
        s|@|#|g;
        s| |@|g;
        #s|---*|—|g;
        s|---*|-|g;
        #s|Z|z|g;
        ' \
    | awk -F'\t' '
        { printf("\"*/%s.lab\"\n",$1);
          printf("@\n");
          N = split($2,txt,"");
          for( n=1; n<=N; n++ ) {
            if( txt[n] == "—" )
              printf("<dash>\n");
            else if( txt[n] == "\"" )
              printf("<dquote>\n");
            else if( txt[n] == "\x27" )
              printf("<quote>\n");
            else if( match(txt[n],"[.0-9]") )
              printf("\"%s\"\n",txt[n]);
            else
              printf("%s\n",txt[n]);
          }
          printf("@\n");
          printf(".\n");
        }';

  return 0;
}

##
## Function that checks and extracts basic info (XMLDIR, IMFILE, IMSIZE, IMRES) from an XML PAGE file and respective image
##
htrsh_pageimg_info () {
  local FN="htrsh_pageimg_info";
  local XML="$1";
  local VAL=""; [ "$htrsh_valschema" = "yes" ] && VAL="-e -s '$htrsh_pagexsd'";
  if [ $# -lt 1 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLFILE";
    } 1>&2;
    return 1;
  elif [ ! -f "$XML" ]; then
    echo "$FN: error: page file not found: $XML" 1>&2;
    return 1;
  elif [ $(eval xmlstarlet val $VAL "$XML" | grep ' invalid$' | wc -l) != 0 ]; then
    echo "$FN: error: invalid page file: $XML" 1>&2;
    return 1;
  fi

  if [ $# -eq 1 ] || [ "$2" != "noinfo" ]; then
    XMLDIR=$(realpath --relative-to=. $(dirname "$XML"));
    IMFILE="$XMLDIR/"$(xmlstarlet sel -t -v //@imageFilename "$XML");
    local XMLSIZE=$(xmlstarlet sel -t -v //@imageWidth -o x -v //@imageHeight "$XML");
    IMSIZE=$(identify -format %wx%h "$IMFILE" 2>/dev/null);

    if [ ! -f "$IMFILE" ]; then
      echo "$FN: error: image file not found: $IMFILE" 1>&2;
      return 1;
    elif [ "$IMSIZE" != "$XMLSIZE" ]; then
      echo "$FN: error: unexpected image size: image=$IMSIZE page=$XMLSIZE" 1>&2;
      return 1;
    fi

    IMRES=$(
      identify -format "%x %y %U\n" "$IMFILE" \
        | awk '
            { if( $3 == "PixelsPerCentimeter" )
                printf("%sx%s",$1,$2);
              else if( $3 == "PixelsPerInch" )
                printf("%gx%g",$1/2.54,$2/2.54);
            }'
      );

     if [ $(echo "$IMRES" | sed 's|.*x||') != $(echo "$IMRES" | sed 's|x.*||') ]; then
       echo "$FN: warning: image resolution different for vertical and horizontal: $IMFILE" 1>&2;
     fi
     IMRES=$(echo "$IMRES" | sed 's|x.*||');
  fi

  return 0;
}

##
## Function that resizes a XML Page file along with its corresponding image
##
htrsh_pageimg_resize () {
  local FN="htrsh_pageimg_resize";
  local INRES="";
  #local OUTRES="118";
  local OUTRES="95";
  local SFACT="";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XML OUTDIR [ OPTIONS ]";
      echo "Options:";
      echo " -i INRES    Input image resolution in ppc (def.=use image metadata)";
      echo " -o OUTRES   Output image resolution in ppc (def.=$OUTRES)";
      echo " -s SFACT    Scaling factor in % (def.=inferred from resolutions)";
    } 1>&2;
    return 1;
  fi

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
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check XML file and image ###
  local XMLDIR IMFILE IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  if [ "$INRES" = "" ] && [ "$IMRES" = "" ]; then
    echo "$FN: error: resolution not given (-i option) and image does not specify resolution: $IMFILE" 1>&2;
    return 1;
  elif [ "$INRES" = "" ] && [ $(printf %.0f $IMRES) -lt 50 ]; then
    echo "$FN: error: image resolution ($IMRES ppc) apparently incorrect since it is unusually low to be a text document image: $IMFILE" 1>&2;
    return 1;
  elif [ ! -d "$OUTDIR" ]; then
    echo "$FN: error: output directory does not exists: $OUTDIR" 1>&2;
    return 1;
  elif [ "$XMLDIR" = $(realpath --relative-to=. "$OUTDIR") ]; then
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

  local IMBASE=$(echo "$IMFILE" | sed 's|.*/||');
  local XMLBASE=$(echo "$XML" | sed 's|.*/||');

  ### Resize image ###
  convert "$IMFILE" -units PixelsPerCentimeter -density $OUTRES -resize $SFACT "$OUTDIR/$IMBASE"; ### don't know why the density has to be set this way

  ### Resize XML Page ###
  cat "$XML" | htrsh_pagexml_resize $SFACT > "$OUTDIR/$XMLBASE";

  return 0;
}

##
## Function that resizes a XML Page file
##
htrsh_pagexml_resize () {
  local FN="htrsh_pagexml_resize";
  local newWidth newHeight scaleFact;
  if [ $# -lt 1 ]; then
    { echo "$FN: error: not enough input arguments";
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
  xmlns:DEFAULT="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"
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
      <xsl:attribute name="points">
        <xsl:for-each select="str:tokenize(@points,'"', '"')">
          <xsl:choose>
            <xsl:when test="position() = 1">
              <xsl:value-of select="round(number($scaleWidth)*number(.))"/>
            </xsl:when>
            <xsl:when test="position() mod 2 = 0">
              <xsl:text>,</xsl:text><xsl:value-of select="round(number($scaleHeight)*number(.))"/>
            </xsl:when>
            <xsl:otherwise>
              <xsl:text> </xsl:text><xsl:value-of select="round(number($scaleWidth)*number(.))"/>
            </xsl:otherwise>
          </xsl:choose> 
        </xsl:for-each>
      </xsl:attribute>
      <xsl:if test="@fpgram">
      <xsl:attribute name="fpgram">
        <xsl:for-each select="str:tokenize(@fpgram,'"', '"')">
          <xsl:choose>
            <xsl:when test="position() = 1">
              <xsl:value-of select="round(number($scaleWidth)*number(.))"/>
            </xsl:when>
            <xsl:when test="position() mod 2 = 0">
              <xsl:text>,</xsl:text><xsl:value-of select="round(number($scaleHeight)*number(.))"/>
            </xsl:when>
            <xsl:otherwise>
              <xsl:text> </xsl:text><xsl:value-of select="round(number($scaleWidth)*number(.))"/>
            </xsl:otherwise>
          </xsl:choose> 
        </xsl:for-each>
      </xsl:attribute>
      </xsl:if>
      <xsl:apply-templates select="@*[local-name() != '"'points'"' and local-name() != '"'fpgram'"'] | node()" />
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>';

  cat /dev/stdin | xmlstarlet tr <( echo "$XSLT" );

  return $?;
}


#-------------------------------------#
# Feature extraction related fuctions #
#-------------------------------------#

##
## Function that cleans and enhances a text image based on regions defined in an XML Page file
##
htrsh_pageimg_clean () {
  local FN="htrsh_pageimg_clean";
  local XPATH='//_:TextRegion[@type="paragraph"]';
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XML OUTDIR [ OPTIONS ]";
      echo "Options:";
      echo " -x XPATH    XPath for region selection (def.=$XPATH)";
    } 1>&2;
    return 1;
  fi

  local XML="$1";
  local OUTDIR="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-x" ]; then
      XPATH="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check XML file and image ###
  local XMLDIR IMFILE IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  if [ ! -d "$OUTDIR" ]; then
    echo "$FN: error: output directory does not exists: $OUTDIR" 1>&2;
    return 1;
  elif [ "$XMLDIR" = $(realpath --relative-to=. "$OUTDIR") ]; then
    echo "$FN: error: output directory has to be different from the one containing the input XML: $XMLDIR" 1>&2;
    return 1;
  fi

  local IMBASE=$(echo "$IMFILE" | sed 's|.*/||; s|\.[^.]*$||;');
  local XMLBASE=$(echo "$XML" | sed 's|.*/||');
  local IXPATH=$(echo "$XPATH" | sed 's|\[\([^[]*\)]|[not(\1)]|');

  local textreg=$(xmlstarlet sel -t -m "$XPATH/_:Coords" -v @points -n \
                    "$XML" 2>/dev/null \
                    | awk '{printf(" -draw \"polyline %s\"",$0)}');
  local othreg=$(xmlstarlet sel -t -m "$IXPATH/_:Coords" -v @points -n \
                   "$XML" 2>/dev/null \
                   | awk '{printf(" -draw \"polyline %s\"",$0)}');

  ### Create mask and enhance selected text regions ###
  eval convert -size $IMSIZE xc:black \
      -fill white -stroke white $textreg \
      -fill black -stroke black $othreg \
      -alpha copy "'$IMFILE'" +swap \
      -compose copy-opacity -composite png:- \
    | imgtxtenh $htrsh_imgtxtenh_opts - "$OUTDIR/$IMBASE.png" 2>&1;
  [ "$?" != 0 ] &&
    echo "$FN: error: problems enhancing image: $IMFILE" 1>&2 &&
    return 1;

  ### Create new XML with image in current directory and PNG extension ###
  xmlstarlet ed -P -u //@imageFilename -v "$IMBASE.png" "$XML" \
    > "$OUTDIR/$XMLBASE";

  return 0;
}

##
## Function that removes noise from borders of a quadrilateral region defined in an XML Page file
##
htrsh_pageimg_quadborderclean () {
  local FN="htrsh_pageimg_quadborderclean";
  local XPATH='//_:TextRegion[@type="paragraph"]';
  local TMPDIR=".";
  local CFG="";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XML OUTIMG [ OPTIONS ]";
      echo "Options:";
      echo " -x XPATH    XPath for region selection (def.=$XPATH)";
      echo " -c CFG      Options for imgpageborder (def.=$CFG)";
      echo " -d TMPDIR   Directory for temporary files (def.=$TMPDIR)";
    } 1>&2;
    return 1;
  fi

  local XML="$1";
  local OUTIMG="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-x" ]; then
      XPATH="$2";
    elif [ "$1" = "-c" ]; then
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
  local XMLDIR IMFILE IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  local IMW=$(echo "$IMSIZE" | sed 's|x.*||');
  local IMH=$(echo "$IMSIZE" | sed 's|.*x||');
  local IMEXT=$(echo "$IMFILE" | sed 's|.*\.||');
  local IMBASE=$(echo "$IMFILE" | sed 's|.*/||; s|\.[^.]*$||;');

  ### Get quadrilaterals ###
  local QUADs=$(xmlstarlet sel -t -m "$XPATH/_:Coords" -v @points -n "$XML");
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
    eval convert -virtual-pixel black -background black "$TMPDIR/${IMBASE}~${n}-pborder.$IMEXT" $persp1 -white-threshold 1% -stroke white -strokewidth 3 -fill none -draw \"polyline $quad $(echo $quad | sed 's| .*||')\" "$TMPDIR/${IMBASE}~${n}-border.$IMEXT";
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
## Function that extracts lines from an image given its XML PAGE file
##
htrsh_pageimg_extract_lines () {
  local FN="htrsh_pageimg_extract_lines";
  local XPATH='//_:TextRegion[@type="paragraph"]';
  local OUTDIR=".";
  local IMFILE="";
  if [ $# -lt 1 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLFILE [ OPTIONS ]";
      echo "Options:";
      echo " -x XPATH    XPath for region selection (def.=$XPATH)";
      echo " -d OUTDIR   Output directory for images (def.=$OUTDIR)";
      echo " -i IMFILE   Extract from provided image (def.=@imageFilename in XML)";
    } 1>&2;
    return 1;
  fi

  local XML="$1";
  shift;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-x" ]; then
      XPATH="$2";
    elif [ "$1" = "-d" ]; then
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
  local XMLDIR IMFILE IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  local NUMLINES=$(xmlstarlet sel -t -v "count($XPATH/_:TextLine/_:Coords)" "$XML");

  if [ "$NUMLINES" -gt 0 ]; then
    local base="$OUTDIR/"$(echo "$IMFILE" | sed 's|.*/||; s|\.[^.]*$||;');
    local extr=$(
      xmlstarlet sel -t -m "$XPATH/_:TextLine/_:Coords" \
          -v ../../@id -o " " -v ../@id -o " " -v @points -n "$XML" \
        | awk -F'[ ,]' -v sz="$IMSIZE" -v base="$base" '
            { mn_x=$3; mx_x=$3;
              mn_y=$4; mx_y=$4;
              for( n=5; n<=NF; n+=2 ) {
                if( mn_x>$n ) mn_x = $n;
                if( mx_x<$n ) mx_x = $n;
                if( mn_y>$(n+1) ) mn_y = $(n+1);
                if( mx_y<$(n+1) ) mx_y = $(n+1);
              }
              fn = sprintf( "%s.%s.%s.png", base, $1, $2 );
              printf(" \\( -size %s xc:black -draw \"polyline", sz );
              for( n=3; n<=NF; n+=2 )
                printf(" %s,%s", $n,$(n+1) );
              printf("\" -alpha copy -clone 0 +swap -composite");
              printf(" -crop %dx%d+%d+%d", mx_x-mn_x+1, mx_y-mn_y+1, mn_x, mn_y );
              printf(" -write \"%s\" -print \"%s\\n\" +delete \\)", fn, fn );
            }');

    eval convert -fill white -stroke white -compose copy-opacity "$IMFILE" $extr null:;
    [ "$?" != 0 ] &&
      echo "$FN: error: line image extraction failed" 1>&2 &&
      return 1;
  fi

  return 0;
}

##
## Function that discretizes a list of features for a given codebook
##
htrsh_feats_discretize () {
  local FN="htrsh_feats_discretize";
  if [ $# -lt 3 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN FEATLST CBOOK OUTDIR";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
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

  local CFG="$htrsh_baseHTKcfg"'
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
# @todo needs to be improved to handle different types of features
htrsh_extract_feats () {
  local FN="htrsh_extract_feats";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN IMGIN FEAOUT";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
  local IMGIN="$1";
  local FEAOUT="$2";

  ### Extract features ###
  if [ "$htrsh_feat" = "dotmatrix" ]; then
    local featcfg="-SwNXg --width $htrsh_dotmatrix_W --height $htrsh_dotmatrix_H --shift=$htrsh_dotmatrix_shift --win-size=$htrsh_dotmatrix_win";
    if [ "$htrsh_dotmatrix_mom" = "yes" ]; then
      paste -d " " <( dotmatrix $featcfg --aux "$IMGIN" ) <( dotmatrix $featcfg "$IMGIN" );
    else
      dotmatrix $featcfg "$IMGIN";
    fi > "$FEAOUT.tfea";
  else
    echo "$FN: error: unknown features type: $htrsh_feat" 1>&2;
    return 1;
  fi

  ### Convert to HTK format ###
  pfl2htk "$FEAOUT.tfea" "$FEAOUT" 2>/dev/null;

  ### gzip features ###
  gzip "$FEAOUT";

  ### Remove temporal files ###
  rm -f "$FEAOUT.tfea";

  return 0;
}

##
## Function that computes a PCA base for a given list of HTK features
##
htrsh_feats_pca () {
  local FN="htrsh_feats_pca";
  local EXCL="[]";
  local RDIM="";
  local TMPDIR=".";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN FEATLST OUTMAT [ OPTIONS ]";
      echo "Options:";
      echo " -e EXCL     Dimensions to exclude in matlab range format (def.=false)";
      echo " -r RDIM     Return base of RDIM dimensions (def.=all)";
      echo " -d TMPDIR   Directory for temporary files (def.=$TMPDIR)";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
  local FEATLST="$1";
  local OUTMAT="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-e" ]; then
      EXCL="$2";
    elif [ "$1" = "-r" ]; then
      RDIM="$2";
    elif [ "$1" = "-d" ]; then
      TMPDIR="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if [ ! -e "$FEATLST" ]; then
    echo "$FN: error: feature list not found: $FEATLST" 1>&2;
    return 1;
  elif [ $(cat "$FEATLST" | wc -l) != $(sed 's|$|.gz|' "$FEATLST" | xargs ls | wc -l) ]; then
    echo "$FN: error: some files in list not found: $FEATLST" 1>&2;
    return 1;
  fi

  local f;
  local FEATS=$(
    for f in $(cat "$FEATLST"); do
      local ff="$TMPDIR/"$(echo $f | sed 's|.*/||');
      zcat "$f.gz" > "$ff";
      echo "$ff";
    done
    );

  local xEXCL=""; [ "$EXCL" != "[]" ] && xEXCL="x(:,$EXCL) = [];";

  { f=$(echo "$FEATS" | head -n 1);
    echo "
      x = readhtk('$f'); $xEXCL
      N = size(x,1);
      s = sum(x)';
      ss = x'*x;
    ";
    for f in $(echo "$FEATS" | tail -n +2); do
      echo "
        x = readhtk('$f'); $xEXCL
        N = N + size(x,1);
        s = s + sum(x)';
        ss = ss + x'*x;
      ";
    done
    echo "
      s = (1/N)*s;
      covm = (1/N)*ss - s*s';
      covm = 0.5*(covm+covm');
      [ B, V ] = eig(covm);
      V = real(diag(V));
      [ srt, idx ] = sort(-1*V);
      V = V(idx);
      B = B(:,idx);
      D = size(covm,1);
    ";
    if [ "$EXCL" != "[]" ]; then
      echo "
        DD = length($EXCL);
        sel = true(D+DD,1);
        sel($EXCL) = false;
        BB = zeros(D+DD);
        BB(sel,sel) = B;
        BB(~sel,~sel) = eye(DD);
        B = BB;
      ";
    fi
    if [ "$RDIM" != "" ]; then
      echo "B = B(:,1:$RDIM);"
    fi
    echo "save -z $OUTMAT B V;";
  } | octave -q;

  [ "$?" != 0 ] &&
    echo "$FN: error: problems computing PCA" 1>&2 &&
    return 1;

  echo "$FEATS" | xargs rm -f;

  return 0;
}

##
## Function that projects a list of features for a given base
##
htrsh_feats_project () {
  local FN="htrsh_feats_project";
  if [ $# -lt 3 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN FEATLST PBASE OUTDIR";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
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

  local f;
  local FEATS=$(
    for f in $(cat "$FEATLST"); do
      local ff="$OUTDIR/"$(echo $f | sed 's|.*/||');
      zcat "$f.gz" > "$ff";
      echo "$ff";
    done
    );

  { echo "load('$PBASE');"
    for f in $(echo "$FEATS"); do
      echo "
        [x,FP,DT,TC,T] = readhtk('$f');
        x = x*B;
        %writehtk('$f',x,FP,TC);
        save('-ascii','$f','x');
      ";
    done
  } | octave -q;

  for f in $(echo "$FEATS"); do
    pfl2htk "$f" "$f~" 2>/dev/null;
    mv "$f~" "$f";
  done

  [ "$?" != 0 ] &&
    echo "$FN: error: problems computing PCA" 1>&2 &&
    return 1;

  gzip -f $FEATS;

  return 0;
}

##
## Function that extracts line features from an image given its XML PAGE file
##
htrsh_pageimg_extract_linefeats () {
  local FN="htrsh_pageimg_extract_linefeats";
  local XPATH='//_:TextRegion[@type="paragraph"]';
  local OUTDIR=".";
  local FEATLST="$OUTDIR/feats.lst";
  local PBASE="";
  local REPLC="yes";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLIN XMLOUT [ OPTIONS ]";
      echo "Options:";
      echo " -x XPATH    XPath for region selection (def.=$XPATH)";
      echo " -d OUTDIR   Output directory for features (def.=$OUTDIR)";
      echo " -l FEATLST  Output list of features to file (def.=$FEATLST)";
      echo " -b PBASE    Project features using given base (def.=false)";
      echo " -c (yes|no) Whether to replace Coords/@points with the features contour (def.=$REPLC)";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
  local XML="$1";
  local XMLOUT="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-x" ]; then
      XPATH="$2";
    elif [ "$1" = "-d" ]; then
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
  local XMLDIR IMFILE IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  ### Extract lines from line coordinates ###
  htrsh_pageimg_extract_lines "$XML" -x "$XPATH" -d "$OUTDIR" > "$OUTDIR/lines.lst";
  [ "$?" != 0 ] && return 1;

  local ed="";
  local FEATS="";

  ### Process each line ###
  local n;
  for n in $(seq 1 $(cat "$OUTDIR/lines.lst" | wc -l)); do
    local ff=$(sed -n ${n}p "$OUTDIR/lines.lst" | sed 's|\.png$||');
    local id=$(echo "$ff" | sed 's|.*\.||');

    echo "$FN: processing line image ${ff}.png";

    ### Clean and trim line image ###
    imglineclean $htrsh_imglineclean_opts ${ff}.png ${ff}_clean.png 2>&1;
    [ "$?" != 0 ] &&
      echo "$FN: error: problems cleaning line image: ${ff}.png" 1>&2 &&
      return 1;

    local bbox=$(identify -format "%wx%h%X%Y" ${ff}_clean.png);
    local bboxsz=$(echo "$bbox" | sed 's|x| |; s|+.*||;');
    local bboxoff=$(echo "$bbox" | sed 's|[0-9]*x[0-9]*||; s|+| |g;');

    ### Estimate skew, slant and affine matrices ###
    local skew=$(convert ${ff}_clean.png +repage -flatten \
                   -deskew 40% -print '%[deskew:angle]\n' \
                   -trim +repage ${ff}_deskew.png);
    local slant=$(imageSlant -v 1 -g -i ${ff}_deskew.png -o ${ff}_deslant.png 2>&1 \
                    | sed -n '/Slant medio/{s|.*: ||;p;}');
    [ "$slant" = "" ] && slant="0";

    local affine=$(echo "
      h = [ $bboxsz ];
      w = h(1);
      h = h(2);
      co = cos(${skew}*pi/180);
      si = sin(${skew}*pi/180);
      s = tan(${slant}*pi/180);
      R0 = [ co,  si, 0 ; -si, co, 0; 0, 0, 1 ];
      R1 = [ co, -si, 0 ;  si, co, 0; 0, 0, 1 ];
      S0 = [ 1, 0, 0 ;  s, 1, 0 ; 0, 0, 1 ];
      S1 = [ 1, 0, 0 ; -s, 1, 0 ; 0, 0, 1 ];
      A0 = R0*S0;
      A1 = S1*R1;

      %mn = round(min([0 0 1; w-1 h-1 1; 0 h-1 1; w-1 0 1]*A0))-1; % Jv3pT: incorrect 5 out of 1117 = 0.45%

      save ${ff}_affine.mat A0 A1;

      printf('%.12g,%.12g,%.12g,%.12g,%.12g,%.12g\n',
        A0(1,1), A0(1,2), A0(2,1), A0(2,2), A0(3,1), A0(3,2) );
      " | octave -q);

    ### Apply affine transformation to image ###
    local mn;
    if [ "$affine" = "1,0,0,1,0,0" ]; then
      ln -s $(echo "$ff" | sed 's|.*/||')_clean.png ${ff}_affine.png;
      mn="0,0";
    else
      mn=$(convert ${ff}_clean.png +repage -flatten \
             -virtual-pixel white +distort AffineProjection ${affine} \
             -shave 1x1 -format %X,%Y -write info: \
             +repage -trim ${ff}_affine.png);
    fi

    ### Add left and right padding ###
    local PADpx=$(echo $IMRES $htrsh_feat_padding | awk '{printf("%.0f",$1*$2/10)}');
    convert ${ff}_affine.png +repage \
      -bordercolor white -border ${PADpx}x \
      +repage ${ff}_fea.png;

    ### Compute features parallelogram ###
    local fbox=$(echo "
      load ${ff}_affine.mat;

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

      printf('%.0f,%.0f %.0f,%.0f %.0f,%.0f %.0f,%.0f\n',
        pt0(1), pt0(2),
        pt1(1), pt1(2),
        pt2(1), pt2(2),
        pt3(1), pt3(2) );
      " | octave -q);

    ### Prepare information to add to XML ###
    #ed="$ed -i '//*[@id=\"${id}\"]/_:Coords' -t attr -n bbox -v '$bbox'";
    #ed="$ed -i '//*[@id=\"${id}\"]/_:Coords' -t attr -n slope -v '$skew'";
    #ed="$ed -i '//*[@id=\"${id}\"]/_:Coords' -t attr -n slant -v '$slant'";
    ed="$ed -i '//*[@id=\"${id}\"]/_:Coords' -t attr -n fpgram -v '$fbox'";

    ### Compute detailed contours if requested ###
    if [ "$htrsh_feat_contour" = "yes" ]; then
      local pts=$(imgccomp -V1 -NJS -A 0.5 -D $htrsh_feat_dilradi -R 5,2,2,2 ${ff}_clean.png);
      ed="$ed -i '//*[@id=\"${id}\"]/_:Coords' -t attr -n fcontour -v '$pts'";
    fi 2>&1;

    ### Extract features ###
    htrsh_extract_feats "${ff}_fea.png" "${ff}.fea";
    [ "$?" != 0 ] && return 1;

    echo "${ff}.fea" >> "$FEATLST";

    [ "$PBASE" != "" ] && FEATS=$( echo "$FEATS"; echo "${ff}.fea"; );

    ### Remove temporal files ###
    [ "$htrsh_keeptmp" -lt 1 ] &&
      rm -f "${ff}.png" "${ff}_clean.png" "${ff}_fea.png";
    [ "$htrsh_keeptmp" -lt 2 ] &&
      rm -f "${ff}_affine.png" "${ff}_affine.mat";
    [ "$htrsh_keeptmp" -lt 3 ] &&
      rm -f "${ff}_deskew.png" "${ff}_deslant.png";
  done

  ### Project features if requested ###
  if [ "$PBASE" != "" ]; then
    htrsh_feats_project <( echo "$FEATS" | sed '/^$/d' ) "$PBASE" "$OUTDIR";
    [ "$?" != 0 ] && return 1;
  fi

  ### Generate new PAGE XML file ###
  eval xmlstarlet ed -P $ed "$XML" > "$XMLOUT";
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
    eval xmlstarlet ed --inplace $ed "$XMLOUT";
  fi

  rm "$OUTDIR/lines.lst";

  return 0;
}


#--------------------------------------#
# HMM model training related functions #
#--------------------------------------#

##
## Function that prints to stdout HMM prototype(s)
##
htrsh_hmm_proto () {
  local FN="htrsh_hmm_proto";
  local PNAME="proto";
  local DISCR="no";
  local RAND="no";
  if [ $# -lt 1 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN (DIMS|CODES) STATES [ OPTIONS ]";
      echo "Options:";
      echo " -n PNAME     Proto name(s), if several separated by '\n' (def.=$PNAME)";
      echo " -D (yes|no)  Whether proto should be discrete (def.=$DISCR)";
      echo " -R (yes|no)  Whether to randomize (def.=$RAND)";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
  local DIMS="$1";
  local STATES="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-n" ]; then
      PNAME="$2";
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

  ### Print prototype(s) ###
  local P="";
  if [ "$DISCR" = "yes" ]; then
    echo '~o <DISCRETE> <StreamInfo> 1 1';
  else
    echo "~o <VECSIZE> $DIMS <USER>";
  fi
  echo "$PNAME" \
    | awk -v D=$DIMS -v S=$STATES -v DISCR=$DISCR -v RAND=$RAND '
        BEGIN { srand('$RANDOM'); }
        { printf("~h \"%s\"\n",$1);
          printf("<BeginHMM>\n");
          printf("<NumStates> %d\n",S+2);
          for(s=1;s<=S;s++) {
            printf("<State> %d\n",s+1);
            if(DISCR=="yes") {
              printf("<NumMixes> %d\n",D);
              printf("<DProb>");
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
              printf("<Mean> %d\n",D);
              if(RAND=="yes") {
                for(d=1;d<=D;d++)
                  printf(d==1?"%g":" %g",(rand()-0.5)/10);
                printf("\n");
                printf("<Variance> %d\n",D);
                for(d=1;d<=D;d++)
                  printf(d==1?"%g":" %g",1+(rand()-0.5)/10);
                printf("\n");
              }
              else {
                for(d=1;d<=D;d++)
                  printf(d==1?"0.0":" 0.0");
                printf("\n");
                printf("<Variance> %d\n",D);
                for(d=1;d<=D;d++)
                  printf(d==1?"1.0":" 1.0");
                printf("\n");
              }
            }
          }
          printf("<TransP> %d\n",S+2);
          printf(" 0.0 1.0");
          for(a=2;a<=S+1;a++)
            printf(" 0.0");
          printf("\n");
          for(aa=1;aa<=S;aa++) {
            for(a=0;a<=S+1;a++)
              if(RAND=="yes") {
                if( a == aa ) {
                  pr=rand();
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
          printf("<EndHMM>\n");
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
  local KEEPROTO="no";
  local KEEPIT="no";
  local RAND="no";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN FEATLST MLF [ OPTIONS ]";
      echo "Options:";
      echo " -d OUTDIR    Directory for output models and temporary files (def.=$OUTDIR)";
      echo " -c CODES     Train discrete model with given codebook size (def.=false)";
      echo " -P PROTO     Use PROTO as initialization prototype (def.=false)";
      echo " -p (yes|no)  Keep initialization prototype (def.=$KEEPROTO)";
      echo " -i (yes|no)  Keep models per iteration (def.=$KEEPIT)";
      echo " -R (yes|no)  Whether to randomize initialization prototype (def.=$RAND)";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
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
    elif [ "$1" = "-p" ]; then
      KEEPROTO="$2";
    elif [ "$1" = "-i" ]; then
      KEEPIT="$2";
    elif [ "$1" = "-R" ]; then
      RAND="$2";
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
    echo "$FN: error: feature list not found: $MLF" 1>&2;
    return 1;
  elif [ "$PROTO" != "" ] && [ ! -e "$PROTO" ]; then
    echo "$FN: error: initialization prototype not found: $PROTO" 1>&2;
    return 1;
  fi

  zcat $(head -n 1 "$FEATLST").gz > "$OUTDIR/tmp.fea";
  local DIMS=$(HList -z -h "$OUTDIR/tmp.fea" | sed -n '/Num Comps:/{s|.*Num Comps: *||;s| .*||;p;}');
  [ "$CODES" != 0 ] && [ $(HList -z -h "$OUTDIR/tmp.fea" | grep DISCRETE_K | wc -l) = 0 ] &&
    echo "$FN: error: features are not discrete" 1>&2 &&
    return 1;
  rm "$OUTDIR/tmp.fea";

  local HMMLST=$(cat "$MLF" \
                   | sed '/^#!MLF!#/d; /^"\*\//d; /^\.$/d; s|^"||; s|"$||;' \
                   | sort -u);

  ### Discrete training ###
  if [ "$CODES" -gt 0 ]; then
    ### Initialization ###
    if [ "$PROTO" != "" ]; then
      cp -p "$PROTO" "$OUTDIR/Macros_hmm.gz";

    else
      htrsh_hmm_proto "$CODES" "$htrsh_hmm_states" -n "$HMMLST" -R $RAND -D yes \
        | gzip > "$OUTDIR/Macros_hmm.gz";

      [ "$KEEPROTO" = "yes" ] && cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/proto.gz";
    fi

    ### Iterate ###
    local i;
    for i in $(seq -f %02.0f 1 $htrsh_hmm_iter); do
      echo "$FN: info: HERest iteration $i";
      HERest $htrsh_HTK_HERest_opts -C <( echo "$htrsh_baseHTKcfg" ) \
        -S "$FEATLST" -I "$MLF" -H "$OUTDIR/Macros_hmm.gz" <( echo "$HMMLST" );
      if [ "$?" != 0 ]; then
        echo "$FN: error: problem with HERest" 1>&2;
        mv "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_i${i}_err.gz"
        return 1;
      fi
      [ "$KEEPIT" = "yes" ] &&
        cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_i$i.gz";
    done
    [ "$KEEPIT" = "yes" ] &&
      cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_i$i.gz";

  ### Continuous training ###
  else
    ### Initialization ###
    if [ "$PROTO" != "" ]; then
      cp -p "$PROTO" "$OUTDIR/Macros_hmm.gz";

    else
      htrsh_hmm_proto "$DIMS" "$htrsh_hmm_states" -R $RAND \
        | gzip > "$OUTDIR/proto";
      HCompV $htrsh_HTK_HCompV_opts -C <( echo "$htrsh_baseHTKcfg" ) -S "$FEATLST" -M "$OUTDIR" "$OUTDIR/proto";

      { zcat "$OUTDIR/proto" \
          | head -n 3;
        cat "$OUTDIR/vFloors";
        zcat "$OUTDIR/proto" \
          | awk -v file=<( echo "$HMMLST" ) \
              'BEGIN {
                 List=0;
                 while(getline m[++List] < file > 0);
               }
               NR>4 {
                 l[NR-4]=$0;
               }
               END {
                for(i=1;i<=List;i++) {
                  print "~h \""m[i]"\"";
                  for(j=1;j<=NR-4;j++)
                    print l[j];
                }
              }';
      } | gzip \
        > "$OUTDIR/Macros_hmm.gz";

      [ "$KEEPROTO" = "yes" ] && cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/proto.gz";
    fi

    ### Iterate for single Gaussian ###
    local i;
    for i in $(seq -f %02.0f 1 $htrsh_hmm_iter); do
      echo "$FN: info: 1 Gaussians HERest iteration $i";
      HERest $htrsh_HTK_HERest_opts -C <( echo "$htrsh_baseHTKcfg" ) \
        -S "$FEATLST" -I "$MLF" -H "$OUTDIR/Macros_hmm.gz" <( echo "$HMMLST" );
      [ "$?" != 0 ] &&
        echo "$FN: error: problem with HERest" 1>&2 &&
        return 1;
      [ "$KEEPIT" = "yes" ] &&
        cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_g001_i$i.gz";
    done
    [ "$KEEPIT" = "yes" ] &&
      cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_g001_i$i.gz";
    [ "$KEEPIT" != "yes" ] &&
      cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_g001.gz";

    ### Iterate duplicating Gaussians ###
    local g="1";
    local gg=$((g+g));
    while [ "$gg" -le "$htrsh_hmm_nummix" ]; do
      ggg=$(printf %.3d $gg);
      echo "$FN: info: duplicating Gaussians to $gg";
      HHEd $htrsh_HTK_HHEd_opts -C <( echo "$htrsh_baseHTKcfg" ) -H "$OUTDIR/Macros_hmm.gz" \
        -M "$OUTDIR" <( echo "MU $gg {*.state[2-$((htrsh_hmm_states-1))].mix}" ) \
        <( echo "$HMMLST" );
      for i in $(seq -f %02.0f 1 $htrsh_hmm_iter); do
        echo "$FN: info: $gg Gaussians HERest iteration $i";
        HERest $htrsh_HTK_HERest_opts -C <( echo "$htrsh_baseHTKcfg" ) \
          -S "$FEATLST" -I "$MLF" -H "$OUTDIR/Macros_hmm.gz" <( echo "$HMMLST" );
        [ "$?" != 0 ] &&
          echo "$FN: error: problem with HERest" 1>&2 &&
          return 1;
        [ "$KEEPIT" = "yes" ] &&
          cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_g${ggg}_i$i.gz";
      done
      [ "$KEEPIT" = "yes" ] &&
        cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_g${ggg}_i$i.gz";
      [ "$KEEPIT" != "yes" ] &&
        cp -p "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_g$ggg.gz";
      g=$gg;
      gg=$((g+g));
    done
  fi

  rm -f "$OUTDIR/proto" "$OUTDIR/vFloors" "$OUTDIR/Macros_hmm.gz";

  return 0;
}

##
## Function that fixes utf8 characters in an HTK recognition file
##
htrsh_fix_rec_utf8 () {
  local FN="htrsh_fix_rec_utf8";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN MODEL RECMLF";
    } 1>&2;
    return 1;
  fi

  local RECOVUTF8=$(
    zcat "$1" \
      | sed -n '/^~h/{ s|^~h "\(.*\)"$|\1|; p; }' \
      | sed -n '
          /^\\[0-9][0-9][0-9]\\[0-9][0-9][0-9]$/ {
            s|^\\\(.*\)\\\(.*\)$|s/\\\\\1\\\\\2/\\o\1\\o\2/g;|;
            p;
          }');

  sed -i "$RECOVUTF8" "$2";

  return 0;
}
