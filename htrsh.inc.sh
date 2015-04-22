#!/bin/bash

##
## Collection of shell functions for Handwritten Text Recognition.
##
## @version $Revision$$Date::             $
## @author Mauricio Villegas <mauvilsa@upv.es>
## @copyright Copyright(c) 2014 to the present, Mauricio Villegas (UPV)
##

unset $(compgen -A variable htrsh_);
unset -f $(compgen -A function htrsh_);

#-----------------------#
# Default configuration #
#-----------------------#

htrsh_valschema="no";
htrsh_pagexsd="http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15/pagecontent.xsd";
#htrsh_pagexsd="/home/mvillegas/DataBases/HTR/British-Library/bin/xsd/pagecontent+.xsd";
#htrsh_pagexsd="http://mvillegas.info/xsd/2013-07-15/pagecontent.xsd";

htrsh_keeptmp="0";

htrsh_text_translit="yes";

htrsh_feat_txtenhcfg="-r 0.16 -w 20 -k 0.1";

htrsh_feat_padding="0.5"; # Left and right white padding in mm for line images
htrsh_feat_contour="yes"; # Whether to compute connected components contours
htrsh_feat_dilradi="0.5"; # Dilation radius in mm for contours

#htrsh_feat_pcadim="20";  # Features reduced dimensionality for PCA

htrsh_feat="dotmatrix";    # Type of features to extract
htrsh_dotmatrix_shift="2"; # Sliding window shift in px, should change this to mm
htrsh_dotmatrix_win="20";  # Sliding window width in px, should change this to mm
htrsh_dotmatrix_W="8";     # Width of normalized frame in px, should change this to mm
htrsh_dotmatrix_H="32";    # Height of normalized frame in px, should change this to mm

htrsh_hmm_states="6"; # Number of HMM states (excluding special initial and final)
htrsh_hmm_nummix="4"; # Number of Gaussian mixture components
htrsh_hmm_iter="4";   # Number of training iterations

htrsh_align_isect="yes"; # Whether to intersect parallelograms with line contour
htrsh_align_chars="yes"; # Whether to align at a character level

htrsh_baseHTKcfg='
HPARMFILTER    = "gzip -d -c $.gz"
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
    | sed 's|^$R|htrsh: r|; s|[$][$]Date: |(|; s| *$|)|;';
}

##
## Function that checks that all required commands are available
##
htrsh_check_req () {
  local FN="htrsh_check_req";
  local cmd;
  for cmd in xmlstarlet convert octave HVite pfl2htk imgtxtenh imglineclean imgpageborder imgccomp imageSlant realpath gzip page_format_generate_contour pca; do
    local c=$(which $cmd);
    if ! [ -e "$c" ]; then
      echo "$FN: WARNING: unable to find command: $cmd" 1>&2;
      #echo "$FN: error: unable to find command: $cmd" 1>&2;
      #return 1;
    fi
  done

  { htrsh_version; echo; } 1>&2;
  { printf "xmlstarlet "; xmlstarlet --version | sed '2,$s|^|  |'; echo; } 1>&2;
  { convert --version | sed -n '1{ s|^Version: ||; p; }'; echo; } 1>&2;
  { octave --version | head -n 1; echo; } 1>&2;
  for cmd in imgtxtenh imglineclean imgpageborder imgccomp; do
   $cmd --version;
  done
  HVite -V;

  return 0;
}


#--------------------------------#
# XML Page manipulation fuctions #
#--------------------------------#

##
## Function that prints to stdout an MLF created from an XML PAGE file
##
# TODO: this needs to be improved a lot
htrsh_page_to_mlf () {
  local FN="htrsh_page_to_mlf";
  local XPATH='//*[@type="paragraph"]';
  if [ $# -lt 1 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLFILE [ OPTIONS ]";
      echo "Options:";
      echo " -x XPATH    XPath for region selection (def.=$XPATH)";
    } 1>&2;
    return 1;
  fi

  local XML="$1";
  shift;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-x" ]; then
      XPATH="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check page and obtain basic info ###
  htrsh_pageimg_info "$XML" noinfo;
  [ "$?" != 0 ] && return 1;

  local TAB=$(printf "\t");
  local PG=$(xmlstarlet sel -t -v //@imageFilename "$XML" | sed 's|.*/||; s|\.[^.]*$||;');
  local NUMLINES=$(xmlstarlet sel -t -v "count($XPATH/_:TextLine/_:TextEquiv)" "$XML");

  if [ "$NUMLINES" -gt 0 ]; then
    echo '#!MLF!#';
    if [ "$htrsh_text_translit" != "yes" ]; then
      xmlstarlet sel -T -B -E utf-8 -t -m "$XPATH/_:TextLine/_:TextEquiv" \
          -o "$PG." -v ../../@id -o "." -v ../@id -o "$TAB" -v . -n "$XML";
    else
      xmlstarlet sel -T -B -E utf-8 -t -m "$XPATH/_:TextLine/_:TextEquiv" \
          -o "$PG." -v ../../@id -o "." -v ../@id -o "$TAB" -v . -n "$XML" \
        | iconv -f utf8 -t ascii//TRANSLIT;
    fi \
      | sed "
          s|   *| |g;
          s| |@|g;
          #s|---*|—|g;
          s|---*|-|g;
          s|Z|z|g;
          " \
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
  fi

  return 0;
}

##
## Function that checks and extracts basic info (XMLDIR, IMFILE, IMSIZE, IMRES) from an XML PAGE file and respective image
##
htrsh_pageimg_info () {
  local FN="htrsh_pageimg_info";
  local XML="$1";
  local VAL=""; [ "$htrsh_valschema" = "yes" ] && VAL="-s '$htrsh_pagexsd'";
  if [ $# -lt 1 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLFILE";
    } 1>&2;
    return 1;
  elif ! [ -f "$XML" ]; then
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

    if ! [ -f "$IMFILE" ]; then
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
  local XMLDIR IMFILE IMSIZE IMRES;
  local FN="htrsh_pageimg_resize";
  #local OUTRES="118";
  local OUTRES="95";
  local INRES="";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XML OUTDIR [ OPTIONS ]";
      echo "Options:";
      echo " -o OUTRES   Output image resolution in ppc (def.=$OUTRES)";
      echo " -i INRES    Input image resolution in ppc (def.=use image metadata)";
    } 1>&2;
    return 1;
  fi

  local XML="$1";
  local OUTDIR="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-o" ]; then
      OUTRES="$2";
    elif [ "$1" = "-i" ]; then
      INRES="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check XML file and image ###
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  if [ "$INRES" = "" ] && [ "$IMRES" = "" ]; then
    echo "$FN: error: resolution not given (-i option) and image does not specify resolution: $IMFILE" 1>&2;
    return 1;
  elif [ "$INRES" = "" ] && [ $(printf %.0f $IMRES) -lt 50 ]; then
    echo "$FN: error: image resolution ($IMRES ppc) apparently incorrect since it is unusually low to be a text document image: $IMFILE" 1>&2;
    return 1;
  elif ! [ -d "$OUTDIR" ]; then
    echo "$FN: error: output directory does not exists: $OUTDIR" 1>&2;
    return 1;
  elif [ "$XMLDIR" = $(realpath --relative-to=. "$OUTDIR") ]; then
    echo "$FN: error: output directory has to be different from the one containing the input XML: $XMLDIR" 1>&2;
    return 1;
  fi

  if [ "$INRES" = "" ]; then
    INRES="$IMRES";
  fi
  local SFACT=$(echo $OUTRES $INRES | awk '{printf("%g%%",100*$1/$2)}');

  local IMBASE=$(echo "$IMFILE" | sed 's|.*/||');
  local XMLBASE=$(echo "$XML" | sed 's|.*/||');

  ### Resize image ###
  convert "$IMFILE" -units PixelsPerCentimeter -density $OUTRES -resize $SFACT "$OUTDIR/$IMBASE"; ### don't know why the density has to be set this way

  ### Resize XML Page ###
  cat "$XML" | htrsh_xmlpage_resize $SFACT > "$OUTDIR/$XMLBASE";

  return 0;
}

##
## Function that resizes a XML Page file
##
htrsh_xmlpage_resize () {
  local FN="htrsh_xmlpage_resize";
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
      <xsl:apply-templates select="@*[local-name() != '"'points'"'] | node()" />
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
  local XMLDIR IMFILE IMSIZE IMRES;
  local FN="htrsh_pageimg_clean";
  #local XPATH='//*[@type="paragraph"]';
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XML OUTDIR [ OPTIONS ]";
      #echo "Options:";
      #echo " -x XPATH    XPath for region selection (def.=$XPATH)";
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
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  if ! [ -d "$OUTDIR" ]; then
    echo "$FN: error: output directory does not exists: $OUTDIR" 1>&2;
    return 1;
  elif [ "$XMLDIR" = $(realpath --relative-to=. "$OUTDIR") ]; then
    echo "$FN: error: output directory has to be different from the one containing the input XML: $XMLDIR" 1>&2;
    return 1;
  fi

  local IMBASE=$(echo "$IMFILE" | sed 's|.*/||; s|\.[^.]*$||;');
  local XMLBASE=$(echo "$XML" | sed 's|.*/||');

  local textreg=$(xmlstarlet sel -t -m '//_:TextRegion[@type="paragraph"]/_:Coords' -v @points -n \
                    "$XML" 2>/dev/null \
                    | awk '{printf(" -draw \"polyline %s\"",$0)}');
  local othreg=$(xmlstarlet sel -t -m '//_:TextRegion[@type!="paragraph"]/_:Coords' -v @points -n \
                   "$XML" 2>/dev/null \
                   | awk '{printf(" -draw \"polyline %s\"",$0)}');

  ### Create mask and enhance selected text regions ###
  eval convert -size $IMSIZE xc:black \
      -fill white -stroke white $textreg \
      -fill black -stroke black $othreg \
      -alpha copy "'$IMFILE'" +swap \
      -compose copy-opacity -composite png:- \
    | imgtxtenh $htrsh_feat_txtenhcfg - "$OUTDIR/$IMBASE.png" 2>&1;
  if [ "$?" != 0 ]; then
    echo "$FN: error: problems enhancing image: $IMFILE" 1>&2;
    return 1;
  fi

  ### Create new XML with image in current directory and PNG extension ###
  xmlstarlet ed -P -u //@imageFilename -v "$IMBASE.png" "$XML" \
    > "$OUTDIR/$XMLBASE";

  return 0;
}

##
## Function that removes noise from borders of a quadrilateral region defined in an XML Page file
##
htrsh_pageimg_quadborderclean () {
  local XMLDIR IMFILE IMSIZE IMRES;
  local FN="htrsh_pageimg_quadborderclean";
  local XPATH='//*[@type="paragraph"]';
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
    if [ $(echo "$quad" | wc -w) != 4 ]; then
      echo "$FN: error: region not a quadrilateral: $XML" 1>&2;
      return 1;
    fi

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
    if [ $? != 0 ]; then
      echo "$FN: error: problems estimating border: $XML" 1>&2;
      return 1;
    fi

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
  local XMLDIR IMFILE IMSIZE IMRES;
  local FN="htrsh_pageimg_extract_lines";
  local XPATH='//*[@type="paragraph"]';
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
    if [ "$?" != 0 ]; then
      echo "$FN: error: line image extraction failed" 1>&2;
      return 1;
    fi
  fi

  return 0;
}

##
## Function that extracts line features from an image given its XML PAGE file
##
htrsh_pageimg_extract_linefeats () {
  local XMLDIR IMFILE IMSIZE IMRES;
  local FN="htrsh_pageimg_extract_linefeats";
  local XPATH='//*[@type="paragraph"]';
  local OUTDIR=".";
  local PBASE="";
  local RDIM="";
  local REPLC="yes";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLIN XMLOUT [ OPTIONS ]";
      echo "Options:";
      echo " -x XPATH    XPath for region selection (def.=$XPATH)";
      echo " -d OUTDIR   Output directory for features (def.=$OUTDIR)";
      echo " -b PBASE    Project features using given base (def.=false)";
      echo " -r RDIM     Reduced dimensionality (def.=from matrix)";
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
    elif [ "$1" = "-b" ]; then
      PBASE="$2";
    elif [ "$1" = "-r" ]; then
      RDIM="$2";
    elif [ "$1" = "-c" ]; then
      REPLC="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  ### Check page and obtain basic info ###
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  ### Extract lines from line coordinates ###
  htrsh_pageimg_extract_lines "$XML" -x "$XPATH" -d "$OUTDIR" > "$OUTDIR/lines.lst";
  [ "$?" != 0 ] && return 1;

  local ed="";

  ### Process each line ###
  local n;
  for n in $(seq 1 $(cat "$OUTDIR/lines.lst" | wc -l)); do
    local ff=$(sed -n ${n}p "$OUTDIR/lines.lst" | sed 's|\.png$||');
    local id=$(echo "$ff" | sed 's|.*\.||');

    echo "$FN: processing line image ${ff}.png";

    ### Clean and trim line image ###
    imglineclean -m 99% ${ff}.png ${ff}_clean.png 2>&1;
    if [ "$?" != 0 ]; then
      echo "$FN: error: problems cleaning line image: ${ff}.png" 1>&2;
      return 1;
    fi

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
    # TODO: move feature extraction to a separate function
    if [ "$htrsh_feat" = "dotmatrix" ]; then
      local featcfg="-SwNXg --width $htrsh_dotmatrix_W --height $htrsh_dotmatrix_H --shift=$htrsh_dotmatrix_shift --win-size=$htrsh_dotmatrix_win";
      dotmatrix $featcfg "${ff}_fea.png" > "${ff}.fea";
      dotmatrix $featcfg --aux "${ff}_fea.png" > "${ff}.mfea";
    else
      echo "$FN: error: unknown features type: $htrsh_feat" 1>&2;
      return 1;
    fi

    ### Project features if requested and concatenate mfea to fea ###
    # TODO: this can be improved considerably
    if [ "$PBASE" != "" ]; then
      { awk '{print NF}' "${ff}.fea" \
          | uniq -c \
          | sed 's|^  *||';
        cat "${ff}.fea";
      } > "${ff}.ofea";

      pca -o PROJ -i ROWS -e ROWS -p "$PBASE" -d "${ff}.ofea" -x "${ff}.pfea";
      if [ "$RDIM" != "" ]; then
        sed '1d; s|  *| |g;' "${ff}.pfea" \
          | awk '{ NF='$((RDIM-4))'; print; }';
      else
        sed '1d; s|  *| |g;' "${ff}.pfea";
      fi | paste -d " " - "${ff}.mfea";
    else
      paste -d " " "${ff}.fea" "${ff}.mfea";
    fi > "${ff}.cfea";

    pfl2htk "${ff}.cfea" "${ff}.fea" 2>&1;
    gzip "${ff}.fea";

    ### Remove temporal files ###
    if [ "$htrsh_keeptmp" -lt 1 ]; then
      rm -f "${ff}.png" "${ff}_clean.png";
      rm -f "${ff}_fea.png";
    fi
    if [ "$htrsh_keeptmp" -lt 2 ]; then
      rm -f "${ff}_affine.png" "${ff}_affine.mat";
    fi
    if [ "$htrsh_keeptmp" -lt 3 ]; then
      rm -f "${ff}_deskew.png" "${ff}_deslant.png";
      rm -f "${ff}".{c,m,o,p}fea;
    fi
  done

  ### Generate new PAGE XML file ###
  eval xmlstarlet ed -P $ed "$XML" > "$XMLOUT";
  if [ "$?" != 0 ]; then
    echo "$FN: error: problems generating XML file: $XMLOUT" 1>&2;
    return 1;
  fi

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
## Function that prints to stdout an HMM prototype
##
# TODO: make this more general, also create discrete
htrsh_hmm_proto () {
  local FN="htrsh_hmm_proto";
  if [ $# -lt 1 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN DIMS STATES";
    } 1>&2;
    return 1;
  fi

  local DIMS="$1";
  local STATES="$2";

  echo "~o <VECSIZE> $DIMS <USER>";
  echo "proto" \
    | awk -v D=$DIMS -v S=$STATES '
        { printf("~h \"%s\"\n",$1);
          printf("<BeginHMM>\n");
          printf("<NumStates> %d\n",S+2);
          for(s=1;s<=S;s++) {
            printf("<State> %d\n",s+1);
            printf("<Mean> %d\n",D);
            for(d=1;d<=D;d++)
              printf(d==1?"0.0":" 0.0");
            printf("\n");
            printf("<Variance> %d\n",D);
            for(d=1;d<=D;d++)
              printf(d==1?"1.0":" 1.0");
            printf("\n");
          }
          printf("<TransP> %d\n",S+2);
          printf(" 0.0 1.0");
          for(a=2;a<=S+1;a++)
            printf(" 0.0");
          printf("\n");
          for(aa=1;aa<=S;aa++) {
            for(a=0;a<=S+1;a++)
              if( a == aa+1 )
                printf(" 0.4");
              else if( a == aa )
                printf(" 0.6");
              else
                printf(" 0.0");
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
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN FEATLST MLF [ OPTIONS ]";
      echo "Options:";
      echo " -d OUTDIR    Directory for temporary files (def.=$OUTDIR)";
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
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if ! [ -e "$FEATLST" ]; then
    echo "$FN: error: feature list not found: $FEATLST" 1>&2;
    return 1;
  elif ! [ -e "$MLF" ]; then
    echo "$FN: error: feature list not found: $MLF" 1>&2;
    return 1;
  fi

  zcat $(head -n 1 "$FEATLST").gz > "$OUTDIR/tmp.fea";
  local DIMS=$(HList -z -h "$OUTDIR/tmp.fea" | sed -n '/Num Comps:/{s|.*Num Comps: *||;s| .*||;p;}');
  rm "$OUTDIR/tmp.fea";

  local HMMLST=$(cat "$MLF" \
                   | sed '/^#!MLF!#/d; /^"\*\//d; /^\.$/d; s|^"||; s|"$||;' \
                   | sort -u);

  ### Initialization ###
  htrsh_hmm_proto "$DIMS" "$htrsh_hmm_states" | gzip > "$OUTDIR/proto";
  HCompV -A -T 1 -C <( echo "$htrsh_baseHTKcfg" ) -f 0.1 -m -S "$FEATLST" -M "$OUTDIR" "$OUTDIR/proto";

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

  ### Iterate for single Gaussian ###
  local i;
  for i in $(seq 1 $htrsh_hmm_iter); do
    HERest -A -T 1 -m 3 -C <( echo "$htrsh_baseHTKcfg" ) \
      -S "$FEATLST" -I "$MLF" -H "$OUTDIR/Macros_hmm.gz" <( echo "$HMMLST" );
  done
  cp "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_001.gz";

  ### Iterate duplicating Gaussians ###
  local g="1";
  local gg=$((g+g));
  while [ "$gg" -le "$htrsh_hmm_nummix" ]; do
    HHEd -A -C <( echo "$htrsh_baseHTKcfg" ) -H "$OUTDIR/Macros_hmm.gz" \
      -M "$OUTDIR" <( echo "MU $gg {*.state[2-$((htrsh_hmm_states-1))].mix}" ) \
      <( echo "$HMMLST" );
    for i in $(seq 1 $htrsh_hmm_iter); do
      HERest -A -T 1 -m 3 -C <( echo "$htrsh_baseHTKcfg" ) \
        -S "$FEATLST" -I "$MLF" -H "$OUTDIR/Macros_hmm.gz" <( echo "$HMMLST" );
    done
    cp "$OUTDIR/Macros_hmm.gz" "$OUTDIR/Macros_hmm_$(printf %.3d $gg).gz";
    g=$gg;
    gg=$((g+g));
  done

  rm -f "$OUTDIR/proto" "$OUTDIR/vFloors" "$OUTDIR/Macros_hmm.gz";

  return 0;
}


#-------------------------------------#
# Viterbi alignment related functions #
#-------------------------------------#

##
## Function that does a forced alignment for a given feature list and model
##
htrsh_pageimg_forcealign_model () {
  local FN="htrsh_pageimg_forcealign_model";
  local TMPDIR=".";
  if [ $# -lt 4 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLIN FEATLST MODEL XMLOUT [ OPTIONS ]";
      echo "Options:";
      echo " -d TMPDIR    Directory for temporary files (def.=$TMPDIR)";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
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

  if ! [ -e "$FEATLST" ]; then
    echo "$FN: error: feature list not found: $FEATLST" 1>&2;
    return 1;
  elif ! [ -e "$MODEL" ]; then
    echo "$FN: error: model file not found: $MODEL" 1>&2;
    return 1;
  fi

  ### Create MLF from XML ###
  htrsh_page_to_mlf "$XML" > "$TMPDIR/$FN.mlf";
  if [ "$?" != 0 ]; then
    echo "$FN: error: problems creating MLF file: $XML" 1>&2;
    return 1;
  fi

  ### Create auxiliary files: HMM list and dictionary ###
  local HMMLST=$(zcat "$MODEL" | sed -n '/^~h "/{ s|^~h "||; s|"$||; p; }');
  local DIC=$(echo "$HMMLST" | awk '{printf("\"%s\" [%s] 1.0 %s\n",$1,$1,$1)}');

  ### Do forced alignment with HVite ###
  HVite -A -T 1 -C <( echo "$htrsh_baseHTKcfg" ) -H "$MODEL" -S "$FEATLST" -m -I "$TMPDIR/$FN.mlf" -i "$TMPDIR/${FN}_aligned.mlf" <( echo "$DIC" ) <( echo "$HMMLST" );
  if [ "$?" != 0 ]; then
    echo "$FN: error: problems aligning with HVite: $XML" 1>&2;
    return 1;
  fi

  ### Prepare command to add alignments to XML ###
  local cmd="xmlstarlet ed -P";

  local n;
  for n in $(seq 1 $(cat "$FEATLST" | wc -l)); do
    local ff=$(sed -n "$n"'{ s|.*/||; s|\.fea$||; p; }' "$FEATLST");
    local id=$(echo "$ff" | sed 's|.*\.||');

    local fbox=$(xmlstarlet sel -t -v "//*[@id=\"${id}\"]/_:Coords/@fpgram" "$XML" | tr ' ' ';');
    local contour=$(xmlstarlet sel -t -v "//*[@id=\"${id}\"]/_:Coords/@points" "$XML");
    local size=$(xmlstarlet sel -t -v //@imageWidth -o x -v //@imageHeight "$XML");

    ### Parse aligned line ###
    local align=$(
      sed -n '
        /\/'${ff}'\.rec"$/{
          :loop;
          N;
          /\n\.$/!b loop;
          s|^[^\n]*\n||;
          s|\n\.$||;
          s|<dquote>|{dquote}|g;
          s|<quote>|{quote}|g;
          s|<GAP>|{GAP}|g;
          s|&|&amp;|g;
          p; q;
        }' "$TMPDIR/${FN}_aligned.mlf" \
        | awk '
            { $1 = $1==0 ? 0 : $1/100000-1 ;
              $2 = $2/100000-1 ;
              #$1 = $1==0 ? 0 : $1-1 ;
              #$2 = $2-1 ;
              NF = 3;
              print;
            }'
      );

    if [ "$align" = "" ]; then
      continue;
    fi

    local a=$(echo "$align" | sed 's| [^ ]*$|;|; s| |,|g; $s|;$||;' | tr -d '\n');

    ### Get parallelogram coordinates of alignments ###
    local coords=$(
      echo "
        fbox = [ $fbox ];
        a = [ $a ];
        dx = ( fbox(2,1)-fbox(1,1) ) / a(end) ;
        dy = ( fbox(2,2)-fbox(1,2) ) / a(end) ;

        xup = round( fbox(1,1) + dx*a );
        yup = round( fbox(1,2) + dy*a );
        xdown = round( fbox(4,1) + dx*a );
        ydown = round( fbox(4,2) + dy*a );

        for n = 1:size(a,1)
          printf('%d,%d %d,%d %d,%d %d,%d\n',
            xdown(n,1), ydown(n,1),
            xup(n,1), yup(n,1),
            xup(n,2), yup(n,2),
            xdown(n,2), ydown(n,2) );
        end
      " | octave -q);

    cmd="$cmd -d '//*[@id=\"${id}\"]/_:TextEquiv'";

    ### Word level alignments ###
    local W=$(echo "$align" | grep ' @$' | wc -l); W=$((W-1));
    local w;
    for w in $(seq 1 $W); do
      local ww=$(printf %.2d $w);
      local p0=$(echo "$align" | grep -n ' @$' | sed -n "${w}{s|:.*||;p;}"); p0=$((p0+1));
      local p1=$(echo "$align" | grep -n ' @$' | sed -n "$((w+1)){s|:.*||;p;}"); p1=$((p1-1));
      local pts;
      if [ "$p0" = "$p1" ]; then
        pts=$(echo "$coords" | sed -n "${p0}p");
      else
        pts=$(echo "$coords" \
          | sed -n "${p0}{s| [^ ]* [^ ]*$||;p;};${p1}{s|^[^ ]* [^ ]* ||;p;};" \
          | tr '\n' ' ' \
          | sed 's| $||');
      fi

      if [ "$htrsh_align_isect" = "yes" ]; then
        pts=$(
          convert -fill white -stroke white \
            \( -size $size xc:black -draw "polyline $contour" \) \
            \( -size $size xc:black -draw "polyline $pts" \) \
            -compose Darken -composite -trim png:- \
          | imgccomp -V0 -JS - );
      fi

      cmd="$cmd -s '//*[@id=\"${id}\"]' -t elem -n TMPNODE";
      cmd="$cmd -i '//TMPNODE' -t attr -n id -v '${id}_w${ww}'";
      cmd="$cmd -s '//TMPNODE' -t elem -n Coords";
      cmd="$cmd -i '//TMPNODE/Coords' -t attr -n points -v '${pts}'";
      cmd="$cmd -r '//TMPNODE' -v Word";

      ### Character level alignments ###
      if [ "$htrsh_align_chars" = "yes" ]; then
        local g=1;
        local c;
        for c in $(seq $p0 $p1); do
          local gg=$(printf %.2d $g);
          local pts=$(echo "$coords" | sed -n "${c}p");
          local text=$(echo "$align" | sed -n "${c}{s|.* ||;p;}" | tr -d '\n');

          cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]' -t elem -n TMPNODE";
          cmd="$cmd -i '//TMPNODE' -t attr -n id -v '${id}_w${ww}_g${gg}'";
          cmd="$cmd -s '//TMPNODE' -t elem -n Coords";
          cmd="$cmd -i '//TMPNODE/Coords' -t attr -n points -v '${pts}'";
          cmd="$cmd -s '//TMPNODE' -t elem -n TextEquiv";
          cmd="$cmd -s '//TMPNODE/TextEquiv' -t elem -n Unicode -v '${text}'";
          cmd="$cmd -r '//TMPNODE' -v Glyph";

          g=$((g+1));
        done
      fi

      local text=$(echo "$align" | sed -n "${p0},${p1}{s|.* ||;p;}" | tr -d '\n');

      cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]' -t elem -n TextEquiv";
      cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]/TextEquiv' -t elem -n Unicode -v '${text}'";
    done

    local text=$(echo "$align" | sed -n '1d; $d; s|.* ||; s|@| |; p;' | tr -d '\n');

    cmd="$cmd -s '//*[@id=\"${id}\"]' -t elem -n TextEquiv";
    cmd="$cmd -s '//*[@id=\"${id}\"]/TextEquiv' -t elem -n Unicode -v '${text}'";
  done

  ### Create new XML including alignments ###
  eval $cmd "$XML" > "$XMLOUT";
  if [ "$?" != 0 ]; then
    echo "$FN: error: problems creating XML file: $XMLOUT" 1>&2;
    return 1;
  fi

  sed -i '
    s|{dquote}|"|g;
    s|{quote}|'"'"'|g;
    s|{lbrace}|{|g;
    s|{rbrace}|}|g;
    s|{at}|@|g;
    ' "$XMLOUT";

  if [ "$htrsh_keeptmp" -lt 1 ]; then
    rm -f "$TMPDIR/$FN.mlf" "$TMPDIR/${FN}_aligned.mlf";
  fi

  return 0;
}

##
## Function that does a forced alignment by extracting features and optionally training a model for the given page
##
htrsh_pageimg_forcealign () {
  local FN="htrsh_pageimg_forcealign";
  local TMPDIR="./__${FN}__";
  local MODEL="";
  local PBASE="";
  local KEEPTMP="no";
  local KEEPAUX="no";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLIN XMLOUT [ OPTIONS ]";
      echo "Options:";
      echo " -d TMPDIR    Directory for temporary files (def.=$TMPDIR)";
      echo " -m MODEL     Use model for aligning (def.=train model for page)";
      echo " -b PBASE     Project features using given base (def.=false)";
      echo " -t (yes|no)  Whether to keep temporary directory and files (def.=$KEEPTMP)";
      echo " -a (yes|no)  Whether to keep auxiliary attributes in XML (def.=$KEEPAUX)";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
  local XML="$1";
  local XMLOUT="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      TMPDIR="$2";
    elif [ "$1" = "-m" ]; then
      MODEL="$2";
    elif [ "$1" = "-b" ]; then
      PBASE="$2";
    elif [ "$1" = "-t" ]; then
      KEEPTMP="$2";
    elif [ "$1" = "-a" ]; then
      KEEPAUX="$2";
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if [ -d "$TMPDIR" ]; then
    echo "$FN: error: temporary directory already exists: $TMPDIR" 1>&2;
    return 1;
  fi

  mkdir -p "$TMPDIR";

  local I=$(xmlstarlet sel -t -v //@imageFilename "$XML");
  local B=$(echo "$XML" | sed 's|.*/||; s|\.[^.]*$||;');

  ### Clean page image ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): enhancing page image ...";
  htrsh_pageimg_clean "$XML" "$TMPDIR" \
    > "$TMPDIR/${B}_pageclean.log";
  [ "$?" != 0 ] && return 1;

  ### Generate contours from baselines ###
  if [ $(xmlstarlet sel -t -v 'count(//*[@type="paragraph"]/_:TextLine/_:Coords[@points and @points!="0,0 0,0"])' "$TMPDIR/$B.xml") = 0 ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): generating line contours from baselines ...";
    page_format_generate_contour -a 75 -d 25 -p "$TMPDIR/$B.xml" -o "$TMPDIR/${B}_contours.xml";
    [ "$?" != 0 ] && echo "$FN: error: page_format_generate_contour failed" 1>&2 && return 1;
  else
    mv "$TMPDIR/$B.xml" "$TMPDIR/${B}_contours.xml";
  fi

  if [ "$PBASE" != "" ]; then
    if ! [ -e "$PBASE" ]; then
      echo "$FN: error: projection base file not found: $PBASE" 1>&2;
      return 1;
    fi
    PBASE="-b $PBASE";
    if [ "$MODEL" != "" ]; then
      PBASE="$PBASE -r "$(zcat "$MODEL" | sed -n '/^<STREAMINFO>/{s|.* ||;p;q;}');
    fi
  fi

  ### Extract line features ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): extracting line features ...";
  htrsh_pageimg_extract_linefeats \
    "$TMPDIR/${B}_contours.xml" "$TMPDIR/${B}_feats.xml" \
    -d "$TMPDIR" $PBASE \
    > "$TMPDIR/${B}_linefeats.log";
  [ "$?" != 0 ] && return 1;
  ls "$TMPDIR"/*.fea.gz | sed 's|\.gz$||' > "$TMPDIR/${B}_feats.lst";

  ### Train HMMs model for this single page ###
  if [ "$MODEL" = "" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): training model for page ...";
    htrsh_page_to_mlf "$TMPDIR/${B}_feats.xml" > "$TMPDIR/${B}_page.mlf";
    [ "$?" != 0 ] && return 1;
    htrsh_hmm_train \
      "$TMPDIR/${B}_feats.lst" "$TMPDIR/${B}_page.mlf" -d "$TMPDIR" \
      > "$TMPDIR/${B}_hmmtrain.log";
    [ "$?" != 0 ] && return 1;
    MODEL="$TMPDIR/Macros_hmm_$(printf %.3d $htrsh_hmm_nummix).gz";
  fi
  if ! [ -e "$MODEL" ]; then
    echo "$FN: error: model file not found: $MODEL" 1>&2;
    return 1;
  fi

  ### Do forced alignment using model ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): doing forced alignment ...";
  htrsh_pageimg_forcealign_model \
    "$TMPDIR/${B}_feats.xml" "$TMPDIR/${B}_feats.lst" "$MODEL" \
    "$XMLOUT" -d "$TMPDIR" \
    > "$TMPDIR/${B}_forcealign.log";
  [ "$?" != 0 ] && return 1;

  [ "$KEEPTMP" != "yes" ] && rm -r "$TMPDIR";

  local ed="-u //@imageFilename -v '$I'";
  [ "$KEEPAUX" != "yes" ] && ed="$ed -d //@fpgram -d //@fcontour";

  eval xmlstarlet ed --inplace $ed "$XMLOUT";

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): finished";

  return 0;
}
