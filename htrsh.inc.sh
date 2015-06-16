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

htrsh_keeptmp="0";

htrsh_text_translit="no";

htrsh_xpath_regions='//_:TextRegion';    # XPATH for selecting Page regions to process
#htrsh_xpath_lines='_:TextLine/_:Coords'; # XPATH for selecting lines (appended to htrsh_xpath_regions)
htrsh_xpath_lines='_:TextLine[_:Coords and _:TextEquiv/_:Unicode]';

htrsh_imgtxtenh_regmask="no";                # Whether to use a region-based processing mask
htrsh_imgtxtenh_opts="-r 0.16 -w 20 -k 0.1"; # Options for imgtxtenh tool
htrsh_imglineclean_opts="-V0 -m 99%";        # Options for imglineclean tool

htrsh_feat_deslope="yes"; # Whether to correct slope per line
htrsh_feat_deslant="yes"; # Whether to correct slant of the text
htrsh_feat_padding="1.0"; # Left and right white padding in mm for line images
htrsh_feat_contour="yes"; # Whether to compute connected components contours
htrsh_feat_dilradi="0.5"; # Dilation radius in mm for contours

htrsh_feat="dotmatrix";    # Type of features to extract
htrsh_dotmatrix_shift="2"; # Sliding window shift in px, should change this to mm
htrsh_dotmatrix_win="20";  # Sliding window width in px, should change this to mm
htrsh_dotmatrix_W="8";     # Width of normalized frame in px, should change this to mm
htrsh_dotmatrix_H="32";    # Height of normalized frame in px, should change this to mm
htrsh_dotmatrix_mom="yes"; # Whether to add moments to features

htrsh_align_chars="no";             # Whether to align at a character level
htrsh_align_isect="yes";            # Whether to intersect parallelograms with line contour
htrsh_align_prefer_baselines="yes"; # Whether to always generate contours from baselines

htrsh_hmm_states="6"; # Number of HMM states (excluding special initial and final)
htrsh_hmm_nummix="4"; # Number of Gaussian mixture components
htrsh_hmm_iter="4";   # Number of training iterations

htrsh_HTK_HERest_opts="-m 2";      # Options for HERest tool
htrsh_HTK_HCompV_opts="-f 0.1 -m"; # Options for HCompV tool
htrsh_HTK_HHEd_opts="";            # Options for HHEd tool
htrsh_HTK_HVite_opts="";           # Options for HVite tool

#htrsh_HTK_HVite_opts="-A -T 1";

htrsh_baseHTKcfg='
HMMDEFFILTER   = "gzip -d -c $"
HMMDEFOFILTER  = "gzip -c > $"
NONUMESCAPES   = T
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
    local c=$(which $cmd);
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
    octave --version | head -n 1;
    HVite -V | grep HVite | cat;
  } 1>&2;

  return 0;
}


#--------------------------------#
# XML Page manipulation fuctions #
#--------------------------------#

##
## Function that prints to stdout in kaldi format the text from an XML Page file
##
htrsh_pagexml_to_kalditxt () {
  local FN="htrsh_pagexml_to_kalditxt";
  local REGSRC="no";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Prints to stdout in kaldi format the text from an XML Page file";
      echo "Usage: $FN XMLFILE [ Options ]";
      echo "Options:";
      echo " -r (yes|no)  Whether to get TextEquiv from regions instead of lines (def.=$REGSRC)";
    } 1>&2;
    return 1;
  fi

  local XML="$1";
  shift;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-r" ]; then
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

  local XPATH IDop;
  if [ "$REGSRC" = "yes" ]; then
    XPATH="$htrsh_xpath_regions/_:TextEquiv/_:Unicode";
    IDop="-o $PG. -v ../../@id";
  else
    XPATH="$htrsh_xpath_regions/_:TextLine/_:TextEquiv/_:Unicode";
    IDop="-o $PG. -v ../../../@id -o . -v ../../@id";
  fi

  [ $(xmlstarlet sel -t -v "count($XPATH)" "$XML") = 0 ] &&
    echo "$FN: error: zero nodes match xpath $XPATH on file: $XML" 1>&2 &&
    return 1;

  if [ "$htrsh_text_translit" != "yes" ]; then
    tr '\t\n' '  ' < "$XML" \
      | xmlstarlet sel -T -B -E utf-8 -t -m "$XPATH" \
          $IDop -o "$TAB" -v . -n;
  else
    tr '\t\n' '  ' < "$XML" \
      | xmlstarlet sel -T -B -E utf-8 -t -m "$XPATH" \
          $IDop -o "$TAB" -v . -n \
      | iconv -f utf8 -t ascii//TRANSLIT;
  fi \
    | sed '
        s|\t  *|\t|;
        s|  *$||;
        s|   *| |g;
        s|\t| |;
        ';

  return 0;
}


##
## Function that prints to stdout an MLF created from an XML Page file
##
htrsh_pagexml_to_mlf () {
  local FN="htrsh_pagexml_to_mlf";
  local REGSRC="no";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Prints to stdout an MLF created from an XML Page file";
      echo "Usage: $FN XMLFILE [ Options ]";
      echo "Options:";
      echo " -r (yes|no)  Whether to get TextEquiv from regions instead of lines (def.=$REGSRC)";
    } 1>&2;
    return 1;
  fi

  local XML="$1";
  shift;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-r" ]; then
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
  local PG=$(xmlstarlet sel -t -v //@imageFilename "$XML" \
               | sed 's|.*/||; s|\.[^.]*$||; s|\[|_|g; s|]|_|g;');

  local XPATH IDop;
  if [ "$REGSRC" = "yes" ]; then
    XPATH="$htrsh_xpath_regions/_:TextEquiv/_:Unicode";
    IDop="-o $PG. -v ../../@id";
  else
    XPATH="$htrsh_xpath_regions/_:TextLine/_:TextEquiv/_:Unicode";
    IDop="-o $PG. -v ../../../@id -o . -v ../../@id";
  fi

  [ $(xmlstarlet sel -t -v "count($XPATH)" "$XML") = 0 ] &&
    echo "$FN: error: zero nodes match xpath $XPATH on file: $XML" 1>&2 &&
    return 1;

  echo '#!MLF!#';
  if [ "$htrsh_text_translit" != "yes" ]; then
    tr '\t\n' '  ' < "$XML" \
      | xmlstarlet sel -T -B -E utf-8 -t -m "$XPATH" \
          $IDop -o "$TAB" -v . -n;
  else
    tr '\t\n' '  ' < "$XML" \
      | xmlstarlet sel -T -B -E utf-8 -t -m "$XPATH" \
          $IDop -o "$TAB" -v . -n \
      | iconv -f utf8 -t ascii//TRANSLIT;
  fi \
    | sed '
        s|\t  *|\t|;
        s|  *$||;
        s|   *| |g;
        ' \
    | awk -F'\t' '
        { printf("\"*/%s.lab\"\n",$1);
          printf("@\n");
          N = split($2,txt,"");
          for( n=1; n<=N; n++ ) {
            if( txt[n] == " " )
              printf("@\n");
            else if( txt[n] == "@" )
              printf("{at}\n");
            else if( txt[n] == "\"" )
              printf("{dquote}\n");
            else if( txt[n] == "\x27" )
              printf("{quote}\n");
            else if( txt[n] == "&" )
              printf("{amp}\n");
            else if( txt[n] == "<" )
              printf("{lt}\n");
            else if( txt[n] == ">" )
              printf("{gt}\n");
            else if( txt[n] == "{" )
              printf("{lbrace}\n");
            else if( txt[n] == "}" )
              printf("{rbrace}\n");
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
## Function that checks and extracts basic info (XMLDIR, IMDIR, IMFILE, XMLBASE, IMBASE, IMEXT, IMSIZE, IMRES) from an XML Page file and respective image
##
htrsh_pageimg_info () {
  local FN="htrsh_pageimg_info";
  local XML="$1";
  local VAL="-e"; [ "$htrsh_valschema" = "yes" ] && VAL="-e -s '$htrsh_pagexsd'";
  if [ $# -lt 1 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Checks and extracts basic info (XMLDIR, IMDIR, IMFILE, XMLBASE, IMBASE, IMEXT, IMSIZE, IMRES) from an XML Page file and respective image";
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
    XMLDIR=$($htrsh_realpath $(dirname "$XML"));
    IMFILE="$XMLDIR/"$(xmlstarlet sel -t -v //@imageFilename "$XML");
    local XMLSIZE=$(xmlstarlet sel -t -v //@imageWidth -o x -v //@imageHeight "$XML");
    IMSIZE=$(identify -format %wx%h "$IMFILE" 2>/dev/null);

    IMDIR=$($htrsh_realpath $(dirname "$IMFILE"));
    XMLBASE=$(echo "$XML" | sed 's|.*/||; s|\.[xX][mM][lL]$||;');
    IMBASE=$(echo "$IMFILE" | sed 's|.*/||; s|\.[^.]*$||;');
    IMEXT=$(echo "$IMFILE" | sed 's|.*\.||');

    [ ! -f "$IMFILE" ] &&
      echo "$FN: error: image file not found: $IMFILE" 1>&2 &&
      return 1;
    [ "$IMSIZE" != "$XMLSIZE" ] &&
      echo "$FN: warning: image size discrepancy: image=$IMSIZE page=$XMLSIZE" 1>&2;

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

     [ $(echo "$IMRES" | sed 's|.*x||') != $(echo "$IMRES" | sed 's|x.*||') ] &&
       echo "$FN: warning: image resolution different for vertical and horizontal: $IMFILE" 1>&2;
     IMRES=$(echo "$IMRES" | sed 's|x.*||');
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
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  if [ "$INRES" = "" ] && [ "$IMRES" = "" ]; then
    echo "$FN: error: resolution not given (-i option) and image does not specify resolution: $IMFILE" 1>&2;
    return 1;
  elif [ "$INRES" = "" ] && [ $(echo $IMRES | awk '{printf("%.0f",$1)}') -lt 50 ]; then
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
  htrsh_pagexml_resize $SFACT < "$XML" \
    | sed '
        s|\( custom="[^"]*\)image-resolution:[^;]*;\([^"]*"\)|\1\2|;
        s| custom="[^:"]*"||;
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

  ### Parse input agruments ###
  local XML="$1";

  local cmd="xmlstarlet ed";
  local id;
  for id in $(xmlstarlet sel -t -m '//_:TextLine/_:Coords[@fpgram]' -v ../@id -n "$XML"); do
    cmd="$cmd -d '//_:TextLine[@id=\"$id\"]/_:Coords/@points'";
    cmd="$cmd -r '//_:TextLine[@id=\"$id\"]/_:Coords/@fpgram' -v points";
  done

  eval $cmd "$XML";

  return 0;
}


#-------------------------------------#
# Feature extraction related fuctions #
#-------------------------------------#

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
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES;
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
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  local IMW=$(echo "$IMSIZE" | sed 's|x.*||');
  local IMH=$(echo "$IMSIZE" | sed 's|.*x||');

  ### Get quadrilaterals ###
  local QUADs=$(xmlstarlet sel -t -m "$htrsh_xpath_regions/_:Coords" -v @points -n "$XML");
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
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  local NUMLINES=$(xmlstarlet sel -t -v "count($htrsh_xpath_regions/$htrsh_xpath_lines/_:Coords)" "$XML");

  if [ "$NUMLINES" -gt 0 ]; then
    local base=$(echo "$OUTDIR/$IMBASE" | sed 's|\[|_|g; s|]|_|g;');

    xmlstarlet sel -t -m "$htrsh_xpath_regions/$htrsh_xpath_lines/_:Coords" \
        -o "$base." -v ../../@id -o "." -v ../@id -o ".png " -v @points -n "$XML" \
      | imgpolycrop "$IMFILE";

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
# @todo handle different types of features
htrsh_extract_feats () {
  local FN="htrsh_extract_feats";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Extracts features from an image";
      echo "Usage: $FN IMGIN FEAOUT";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
  local IMGIN="$1";
  local FEAOUT="$2";

  ### Extract features ###
  if [ "$htrsh_feat" = "dotmatrix" ]; then
    local featcfg="-S --htk --width $htrsh_dotmatrix_W --height $htrsh_dotmatrix_H --shift=$htrsh_dotmatrix_shift --win-size=$htrsh_dotmatrix_win -i";
    if [ "$htrsh_dotmatrix_mom" = "yes" ]; then
      dotmatrix -m $featcfg "$IMGIN";
    else
      dotmatrix $featcfg "$IMGIN";
    fi > "$FEAOUT";
  else
    echo "$FN: error: unknown features type: $htrsh_feat" 1>&2;
    return 1;
  fi

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

  ### Parse input agruments ###
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
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  [ ! -e "$FEATDIR" ] &&
    echo "$FN: error: features directory not found: $FEATDIR" 1>&2 &&
    return 1;

  local FBASE=$(echo "$FEATDIR/$IMBASE" | sed 's|\[|_|g; s|]|_|g;');

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
    eval HCopy $ff "$FBASE.$id.fea";

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

  ### Parse input agruments ###
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
    #echo "save('$OUTMAT','B','V','mu');";
  } | octave -q;

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

  { echo "load('$PBASE');"
    local f;
    for f in $(< "$FEATLST"); do
      echo "
        [x,FP,DT,TC,T] = readhtk('$f');
        x = (x-repmat(mu,size(x,1),1))*B;
        writehtk('$f',x,FP,TC);
        %save('-ascii','$f','x');
      ";
    done
  } | octave -q;

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

  ### Parse input agruments ###
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
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  ### Extract lines from line coordinates ###
  local LINEIMGS=$(htrsh_pageimg_extract_lines "$XML" -d "$OUTDIR");
  [ "$?" != 0 ] && return 1;

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
      " | octave -q);

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

      printf('%.0f,%.0f %.0f,%.0f %.0f,%.0f %.0f,%.0f\n',
        pt0(1), pt0(2),
        pt1(1), pt1(2),
        pt2(1), pt2(2),
        pt3(1), pt3(2) );
      " | octave -q);

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

    ### Extract features ###
    htrsh_extract_feats "${ff}_fea.png" "$ff.fea";
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

  return 0;
}


#--------------------------------------#
# HMM model training related functions #
#--------------------------------------#

##
## Function that prints to stdout HMM prototype(s) in HTK format
##
htrsh_hmm_proto () {
  local FN="htrsh_hmm_proto";
  local PNAME="proto";
  local DISCR="no";
  local RAND="no";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Prints to stdout HMM prototype(s) in HTK format";
      echo "Usage: $FN (DIMS|CODES) STATES [ Options ]";
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
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Trains HMMs for a given feature list and mlf";
      echo "Usage: $FN FEATLST MLF [ Options ]";
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
    echo "$FN: error: MLF file not found: $MLF" 1>&2;
    return 1;
  elif [ "$PROTO" != "" ] && [ ! -e "$PROTO" ]; then
    echo "$FN: error: initialization prototype not found: $PROTO" 1>&2;
    return 1;
  fi

  local DIMS=$(HList -z -h "$(head -n 1 "$FEATLST")" | sed -n '/Num Comps:/{s|.*Num Comps: *||;s| .*||;p;}');
  [ "$CODES" != 0 ] && [ $(HList -z -h "$(head -n 1 "$FEATLST")" | grep DISCRETE_K | wc -l) = 0 ] &&
    echo "$FN: error: features are not discrete" 1>&2 &&
    return 1;

  local HMMLST=$(cat "$MLF" \
                   | sed '/^#!MLF!#/d; /^"\*\//d; /^\.$/d; s|^"||; s|"$||;' \
                   | sort -u);

  ### Discrete training ###
  if [ "$CODES" -gt 0 ]; then
    ### Initialization ###
    if [ "$PROTO" != "" ]; then
      cp -p "$PROTO" "$OUTDIR/Macros_hmm.gz";

    else
      if [ "$RAND" = "yes" ]; then
        htrsh_hmm_proto "$CODES" "$htrsh_hmm_states" -D yes -n "$HMMLST" -R $RAND \
          | gzip > "$OUTDIR/Macros_hmm.gz";
      else
        htrsh_hmm_proto "$CODES" "$htrsh_hmm_states" -D yes \
          | gzip > "$OUTDIR/proto.gz";
        HInit -C <( echo "$htrsh_baseHTKcfg" ) -i 0 -S "$FEATLST" -M "$OUTDIR" "$OUTDIR/proto.gz";
        mv "$OUTDIR/proto.gz" "$OUTDIR/proto";

        # @todo not tested yet so test it
        { zcat "$OUTDIR/proto" \
            | head -n 3;
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
                  for(i=1;i<=List;i++)
                    if( m[i] != "" ) {
                      print "~h \""m[i]"\"";
                      for(j=1;j<=NR-4;j++)
                        print l[j];
                    }
                }';
        } | gzip \
          > "$OUTDIR/Macros_hmm.gz";
      fi

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
      # @todo implement random ?
      htrsh_hmm_proto "$DIMS" "$htrsh_hmm_states" \
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
                for(i=1;i<=List;i++)
                  if( m[i] != "" ) {
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
    s|{dquote}|"|g;
    s|{quote}|'"'"'|g;
    s|{amp}|\&amp;|g;
    s|{lt}|\&lt;|g;
    s|{gt}|\&gt;|g;
    s|{lbrace}|{|g;
    s|{rbrace}|}|g;
    ' "$1";

  return 0;
}


#-------------------------------------#
# Viterbi alignment related functions #
#-------------------------------------#

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

  ### Check XML file and image ###
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;
  local B=$(echo "$XMLBASE" | sed 's|\[|_|g; s|]|_|g;');

  ### Create MLF from XML ###
  htrsh_pagexml_to_mlf "$XML" > "$TMPDIR/$B.mlf";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating MLF file: $XML" 1>&2 &&
    return 1;

  ### Create auxiliary files: HMM list and dictionary ###
  local HMMLST=$(zcat "$MODEL" | sed -n '/^~h "/{ s|^~h "||; s|"$||; p; }');
  local DIC=$(echo "$HMMLST" | awk '{printf("\"%s\" [%s] 1.0 %s\n",$1,$1,$1)}');

  ### Do forced alignment with HVite ###
  HVite $htrsh_HTK_HVite_opts -C <( echo "$htrsh_baseHTKcfg" ) -H "$MODEL" -S "$FEATLST" -m -I "$TMPDIR/$B.mlf" -i "$TMPDIR/${B}_aligned.mlf" <( echo "$DIC" ) <( echo "$HMMLST" );
  [ "$?" != 0 ] &&
    echo "$FN: error: problems aligning with HVite: $XML" 1>&2 &&
    return 1;

  ### Prepare command to add alignments to XML ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): generating Page XML with alignments ..." 1>&2;
  local cmd="xmlstarlet ed -P -d //_:Word";
  #cp "$XML" "$XMLOUT";

  [ "$htrsh_align_isect" = "yes" ] &&
    local size=$(xmlstarlet sel -t -v //@imageWidth -o x -v //@imageHeight "$XML");

  local ids=$(xmlstarlet sel -t -m //_:TextLine/_:Coords/@fpgram \
                -v ../../@id -n "$XML");

  #local TS=$(($(date +%s%N)/1000000));

  local aligns=$(
    awk '
      { if( NR > 1 ) {
          if( match( $0, /\.rec"$/ ) )
            LID = gensub(/.*\.([^.]+)\.rec"$/, "\\1", "", $0 );
          else if( $0 != "." ) {
            NF = 3;
            $2 = $2/100000-1 ;
            $1 = $1==0 ? 0 : $1/100000-1 ;
            $1 = ( LID " " $1 );
            print;
          }
        }
      }
      ' "$TMPDIR/${B}_aligned.mlf"
      );

  local acoords=$(
    echo "
      fpgram = [ "$(
        xmlstarlet sel -t -m //@fpgram -v . -n "$XML" \
          | sed 's| |,|g; $!s|$|;|;' \
          | tr -d '\n'
          )" ];
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

        xup = round( f(1,1) + dx*a );
        yup = round( f(1,2) + dy*a );
        xdown = round( f(4,1) + dx*a );
        ydown = round( f(4,2) + dy*a );

        for n = 1:size(a,1)
          printf('%d %d,%d %d,%d %d,%d %d,%d\n',
            l,
            xdown(n,1), ydown(n,1),
            xup(n,1), yup(n,1),
            xup(n,2), yup(n,2),
            xdown(n,2), ydown(n,2) );
        end
      end" \
    | octave -q \
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

  local n;
  for n in $(seq 1 $(wc -l < "$FEATLST")); do
    local id=$(sed -n "$n"'{ s|.*\.\([^.]*\)\.fea$|\1|; p; }' "$FEATLST");

    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): alignments for line $n (id=$id) ..." 1>&2;

    [ "$htrsh_align_isect" = "yes" ] &&
      local contour=$(xmlstarlet sel -t -v '//*[@id="'$id'"]/_:Coords/@points' "$XML");

    local align=$(echo "$aligns" | sed -n "/^$id /{ s|^$id ||; p; }");
    [ "$align" = "" ] && continue;
    local coords=$(echo "$acoords" | sed -n "/^$id /{ s|^$id ||; p; }");

    #local cmd="xmlstarlet ed -P --inplace -d '//*[@id=\"${id}\"]/_:TextEquiv'";
    #cmd="$cmd -d '//*[@id=\"$id\"]/_:TextEquiv'";

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

      [ "$htrsh_align_isect" = "yes" ] &&
        pts=$(
          eval $(
            { echo "$pts";
              echo "$contour";
            } | awk -F'[ ,]' -v sz=$size '
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
              }
              ' ) \
            | imgccomp -V0 -JS - );

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
          local text=$(echo "$align" | sed -n "$c{s|.* ||;p;}" | tr -d '\n');

          cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]' -t elem -n TMPNODE";
          cmd="$cmd -i '//TMPNODE' -t attr -n id -v '${id}_w${ww}_g${gg}'";
          cmd="$cmd -s '//TMPNODE' -t elem -n Coords";
          cmd="$cmd -i '//TMPNODE/Coords' -t attr -n points -v '$pts'";
          cmd="$cmd -s '//TMPNODE' -t elem -n TextEquiv";
          cmd="$cmd -s '//TMPNODE/TextEquiv' -t elem -n Unicode -v '$text'";
          cmd="$cmd -r '//TMPNODE' -v Glyph";

          g=$((g+1));
        done
      fi

      #TE=$(($(date +%s%N)/1000000)); echo "time 5: $((TE-TS)) ms" 1>&2; TS="$TE";

      local text=$(echo "$align" | sed -n "$pS,$pE{s|.* ||;p;}" | tr -d '\n');

      cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]' -t elem -n TextEquiv";
      cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]/TextEquiv' -t elem -n Unicode -v '$text'";

      #TE=$(($(date +%s%N)/1000000)); echo "time 6: $((TE-TS)) ms" 1>&2; TS="$TE";
    done

    local text=$(echo "$align" | sed -n '1d; $d; s|.* ||; s|@| |; p;' | tr -d '\n');

    cmd="$cmd -m '//*[@id=\"$id\"]/_:TextEquiv' '//*[@id=\"$id\"]'";
    #eval $cmd "$XMLOUT";
  done

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): edit XML ..." 1>&2;
  ### Create new XML including alignments ###
  eval $cmd "$XML" > "$XMLOUT";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating XML file: $XMLOUT" 1>&2 &&
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
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Does a line by line forced alignment given only a page with baselines or contours and optionally a model";
      echo "Usage: $FN XMLIN XMLOUT [ Options ]";
      echo "Options:";
      echo " -d TMPDIR    Directory for temporary files (def.=$TMPDIR)";
      echo " -i INRES     Input image resolution in ppc (def.=use image metadata)";
      echo " -m MODEL     Use model for aligning (def.=train model for page)";
      echo " -b PBASE     Project features using given base (def.=false)";
      echo " -e (yes|no)  Whether to enhance the image using imgtxtenh (def.=$ENHIMG)";
      echo " -p (yes|no)  Whether to compute PCA for image and project features (def.=$DOPCA)";
      echo " -t (yes|no)  Whether to keep temporary directory and files (def.=$KEEPTMP)";
      echo " -a (yes|no)  Whether to keep auxiliary attributes in XML (def.=$KEEPAUX)";
      #echo " -q (yes|no)  Whether to clean quadrilateral border of regions (def.=$QBORD)";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
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
    else
      echo "$FN: error: unexpected input argument: $1" 1>&2;
      return 1;
    fi
    shift 2;
  done

  if [ -d "$TMPDIR" ]; then
    echo -n "$FN: temporary directory ($TMPDIR) already exists, continue? " 1>&2;
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
  local XMLDIR IMDIR IMFILE XMLBASE IMBASE IMEXT IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  #local RCNT=$(xmlstarlet sel -t -v "count($htrsh_xpath_regions/_:TextEquiv/_:Unicode)" "$XML");
  local RCNT="0";
  local LCNT=$(xmlstarlet sel -t -v "count($htrsh_xpath_regions/_:TextLine/_:TextEquiv/_:Unicode)" "$XML");
  [ "$RCNT" = 0 ] && [ "$LCNT" = 0 ] &&
    echo "$FN: error: no TextEquiv/Unicode nodes for processing: $XML" 1>&2 &&
    return 1;

  local WGCNT=$(xmlstarlet sel -t -v 'count(//_:Word)' -o ' ' -v 'count(//_:Glyph)' "$XML");
  [ "$WGCNT" != "0 0" ] &&
    echo "$FN: warning: input already contains Word and/or Glyph information: $XML" 1>&2;

  local AREG="no"; [ "$LCNT" = 0 ] && AREG="yes";

  mkdir -p "$TMPDIR";

  local B=$(echo "$XMLBASE" | sed 's|\[|_|g; s|]|_|g;');

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): processing page: $XML";

  ### Clean page image ###
  if [ "$ENHIMG" = "yes" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): enhancing page image ...";
    [ "$INRES" != "" ] && INRES="-i $INRES";
    htrsh_pageimg_clean "$XML" "$TMPDIR" $INRES \
      > "$TMPDIR/${XMLBASE}_pageclean.log";
    [ "$?" != 0 ] &&
      echo "$FN: error: more info might be in file $TMPDIR/${XMLBASE}_pageclean.log" 1>&2 &&
      return 1;
  else
    cp -p "$XML" "$IMFILE" "$TMPDIR";
  fi

  ### Clean quadrilateral borders ###
  if [ "$QBORD" = "yes" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): cleaning quadrilateral borders ...";
    htrsh_pageimg_quadborderclean "$TMPDIR/${XMLBASE}.xml" "$TMPDIR/${IMBASE}_nobord.png" -d "$TMPDIR";
    [ "$?" != 0 ] && return 1;
    mv "$TMPDIR/${IMBASE}_nobord.png" "$TMPDIR/$IMBASE.png";
  fi

  ### Generate contours from baselines ###
  if [ $(xmlstarlet sel -t -v 'count(//'"$htrsh_xpath_regions"'/_:TextLine/_:Coords[@points and @points!="0,0 0,0"])' "$TMPDIR/$XMLBASE.xml") = 0 ] ||
     [ "$htrsh_align_prefer_baselines" = "yes" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): generating line contours from baselines ...";
    page_format_generate_contour -a 75 -d 25 -p "$TMPDIR/$XMLBASE.xml" -o "$TMPDIR/${XMLBASE}_contours.xml";
    [ "$?" != 0 ] &&
      echo "$FN: error: page_format_generate_contour failed" 1>&2 &&
      return 1;
  else
    mv "$TMPDIR/$XMLBASE.xml" "$TMPDIR/${XMLBASE}_contours.xml";
  fi

  ### Extract line features ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): extracting line features ...";
  htrsh_pageimg_extract_linefeats \
    "$TMPDIR/${XMLBASE}_contours.xml" "$TMPDIR/${XMLBASE}_feats.xml" \
    -d "$TMPDIR" -l "$TMPDIR/${B}_feats.lst" \
    > "$TMPDIR/${XMLBASE}_linefeats.log";
  [ "$?" != 0 ] &&
    echo "$FN: error: more info might be in file $TMPDIR/${XMLBASE}_linefeats.log" 1>&2 &&
    return 1;

  ### Compute PCA and project features ###
  if [ "$DOPCA" = "yes" ]; then
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
    htrsh_pagexml_to_mlf "$TMPDIR/${XMLBASE}_feats.xml" -r $AREG > "$TMPDIR/${B}_page.mlf";
    [ "$?" != 0 ] && return 1;
    htrsh_hmm_train \
      "$TMPDIR/${B}_feats.lst" "$TMPDIR/${B}_page.mlf" -d "$TMPDIR" \
      > "$TMPDIR/${XMLBASE}_hmmtrain.log";
    [ "$?" != 0 ] &&
      echo "$FN: error: more info might be in file $TMPDIR/${XMLBASE}_hmmtrain.log" 1>&2 &&
      return 1;
    MODEL="$TMPDIR/Macros_hmm_g$(printf %.3d $htrsh_hmm_nummix).gz";
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

  eval xmlstarlet ed --inplace $ed "$XMLOUT";

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): finished, $(( $(date +%s)-TS )) seconds";

  return 0;
}
