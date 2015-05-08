#!/bin/bash

htrsh_align_chars="no"; # Whether to align at a character level
htrsh_align_isect="yes"; # Whether to intersect parallelograms with line contour

#htrsh_hmm_iter="10";
htrsh_keeptmp="1";
htrsh_imglineclean_opts="-m 99% -b 0";

#htrsh_feat_deslant="no";

htrsh_pagexsd="/home/mvillegas/work/prog/mvsh/HTR/xsd/pagecontent+.xsd";

htrsh_feat_contour=$htrsh_align_isect;


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
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating MLF file: $XML" 1>&2 &&
    return 1;

  ### Create auxiliary files: HMM list and dictionary ###
  local HMMLST=$(zcat "$MODEL" | sed -n '/^~h "/{ s|^~h "||; s|"$||; p; }');
  local DIC=$(echo "$HMMLST" | awk '{printf("\"%s\" [%s] 1.0 %s\n",$1,$1,$1)}');

  ### Do forced alignment with HVite ###
  HVite $htrsh_HTK_HVite_opts -C <( echo "$htrsh_baseHTKcfg" ) -H "$MODEL" -S "$FEATLST" -m -I "$TMPDIR/$FN.mlf" -i "$TMPDIR/${FN}_aligned.mlf" <( echo "$DIC" ) <( echo "$HMMLST" );
  [ "$?" != 0 ] &&
    echo "$FN: error: problems aligning with HVite: $XML" 1>&2 &&
    return 1;

  htrsh_fix_rec_utf8 "$MODEL" "$TMPDIR/${FN}_aligned.mlf";

  ### Prepare command to add alignments to XML ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): generating Page XML with alignments ..." 1>&2;
  local cmd="xmlstarlet ed -P -d //_:Word -d //_:Glyph";
  #cp "$XML" "$XMLOUT";

  [ "$htrsh_align_isect" = "yes" ] &&
    local size=$(xmlstarlet sel -t -v //@imageWidth -o x -v //@imageHeight "$XML");

  local M="$TMPDIR/_forcealign";
  mathd_init "$M" -D "$htrsh_math_daemon";

  local n;
  for n in $(seq 1 $(cat "$FEATLST" | wc -l)); do
    local ff=$(sed -n "$n"'{ s|.*/||; s|\.fea$||; p; }' "$FEATLST");
    local id=$(echo "$ff" | sed 's|.*\.||');

    local fbox=$(xmlstarlet sel -t -v "//*[@id=\"${id}\"]/_:Coords/@fpgram" "$XML" | tr ' ' ';');
    [ "$htrsh_align_isect" = "yes" ] &&
      local contour=$(xmlstarlet sel -t -v "//*[@id=\"${id}\"]/_:Coords/@points" "$XML");

    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): alignments for line $n ..." 1>&2;
    ### Parse aligned line ###
    local align=$(
      sed -n '
        /\/'${ff}'\.rec"$/{
          :loop;
          N;
          /\n\.$/!b loop;
          s|^[^\n]*\n||;
          s|\n\.$||;
          #s|<dquote>|{dquote}|g;
          #s|<quote>|{quote}|g;
          #s|<GAP>|{GAP}|g;
          #s|&|&amp;|g;
          p; q;
        }' "$TMPDIR/${FN}_aligned.mlf" \
        | awk '
            { $1 = $1==0 ? 0 : $1/100000-1 ;
              $2 = $2/100000-1 ;
              NF = 3;
              print;
            }'
      );

    if [ "$align" = "" ]; then
      continue;
    fi

    local a=$(echo "$align" | sed 's| [^ ]*$|;|; s| |,|g; $s|;$||;' | tr -d '\n');

    ### Get parallelogram coordinates of alignments ###
    #local coords=$(
    #  echo "
    #    fbox = [ $fbox ];
    #    a = [ $a ];
    #    dx = ( fbox(2,1)-fbox(1,1) ) / a(end) ;
    #    dy = ( fbox(2,2)-fbox(1,2) ) / a(end) ;

    #    xup = round( fbox(1,1) + dx*a );
    #    yup = round( fbox(1,2) + dy*a );
    #    xdown = round( fbox(4,1) + dx*a );
    #    ydown = round( fbox(4,2) + dy*a );

    #    for n = 1:size(a,1)
    #      printf('%d,%d %d,%d %d,%d %d,%d\n',
    #        xdown(n,1), ydown(n,1),
    #        xup(n,1), yup(n,1),
    #        xup(n,2), yup(n,2),
    #        xdown(n,2), ydown(n,2) );
    #    end
    #  " | octave -q);

    mathd_input;
      echo "
        fbox = [ $fbox ];
        a = [ $a ];
        dx = ( fbox(2,1)-fbox(1,1) ) / a(end) ;
        dy = ( fbox(2,2)-fbox(1,2) ) / a(end) ;

        xup = round( fbox(1,1) + dx*a );
        yup = round( fbox(1,2) + dy*a );
        xdown = round( fbox(4,1) + dx*a );
        ydown = round( fbox(4,2) + dy*a );

        fi = fopen('${M}_coords.txt','w');
        for n = 1:size(a,1)
          fprintf(fi,'%d,%d %d,%d %d,%d %d,%d\n',
            xdown(n,1), ydown(n,1),
            xup(n,1), yup(n,1),
            xup(n,2), yup(n,2),
            xdown(n,2), ydown(n,2) );
        end
        fclose(fi);
      " >> $M.m;
    mathd_exec;
    local coords=$(cat ${M}_coords.txt);

    #local cmd="xmlstarlet ed -P --inplace -d '//*[@id=\"${id}\"]/_:TextEquiv'";
    cmd="$cmd -d '//*[@id=\"${id}\"]/_:TextEquiv'";

    ### Word level alignments ###
    local W=$(echo "$align" | grep ' @$' | wc -l); W=$((W-1));
    local w;
    for w in $(seq 1 $W); do
      #echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): alignments for line $n word $w ..." 1>&2;
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

      [ "$htrsh_align_isect" = "yes" ] &&
        pts=$(
          convert -fill white -stroke white \
              \( -size $size xc:black -draw "polyline $contour" \) \
              \( -size $size xc:black -draw "polyline $pts" \) \
              -compose Darken -composite -trim png:- \
            | imgccomp -V0 -JS - );

      cmd="$cmd -s '//*[@id=\"${id}\"]' -t elem -n TMPNODE";
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

      local text=$(echo "$align" | sed -n "$pS,$pE{s|.* ||;p;}" | tr -d '\n');

      cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]' -t elem -n TextEquiv";
      cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]/TextEquiv' -t elem -n Unicode -v '$text'";
    done

    local text=$(echo "$align" | sed -n '1d; $d; s|.* ||; s|@| |; p;' | tr -d '\n');

    cmd="$cmd -s '//*[@id=\"${id}\"]' -t elem -n TextEquiv";
    cmd="$cmd -s '//*[@id=\"${id}\"]/TextEquiv' -t elem -n Unicode -v '$text'";
    #eval $cmd "$XMLOUT";
  done

  mathd_term;

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): edit XML ..." 1>&2;
  ### Create new XML including alignments ###
  eval $cmd "$XML" > "$XMLOUT";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating XML file: $XMLOUT" 1>&2 &&
    return 1;

  htrsh_fix_rec_names "$XMLOUT";

  [ "$htrsh_keeptmp" -lt 1 ] &&
    rm -f "$TMPDIR/$FN.mlf" "$TMPDIR/${FN}_aligned.mlf";

  return 0;
}

##
## Function that does a forced alignment at a region level for a given XML Page, feature list and model
##
htrsh_pageimg_forcealign_regions () {
  local FN="htrsh_pageimg_forcealign_regions";
  local TMPDIR=".";
  if [ $# -lt 4 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLIN FEATLST NFRAMES MODEL XMLOUT [ OPTIONS ]";
      echo "Options:";
      echo " -d TMPDIR    Directory for temporary files (def.=$TMPDIR)";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
  local XML="$1";
  local FEATLST="$2";
  local NFRAMES="$3";
  local MODEL="$4";
  local XMLOUT="$5";
  shift 5;
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
  htrsh_page_to_mlf "$XML" -r yes > "$TMPDIR/$FN.mlf";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating MLF file: $XML" 1>&2 &&
    return 1;

  ### Create auxiliary files: HMM list and dictionary ###
  local HMMLST=$(zcat "$MODEL" | sed -n '/^~h "/{ s|^~h "||; s|"$||; p; }');
  local DIC=$(echo "$HMMLST" | awk '{printf("\"%s\" [%s] 1.0 %s\n",$1,$1,$1)}');

  ### Do forced alignment with HVite ###
  HVite $htrsh_HTK_HVite_opts -C <( echo "$htrsh_baseHTKcfg" ) -H "$MODEL" -S "$FEATLST" -m -I "$TMPDIR/$FN.mlf" -i "$TMPDIR/${FN}_aligned.mlf" <( echo "$DIC" ) <( echo "$HMMLST" );
  [ "$?" != 0 ] &&
    echo "$FN: error: problems aligning with HVite: $XML" 1>&2 &&
    return 1;

  htrsh_fix_rec_utf8 "$MODEL" "$TMPDIR/${FN}_aligned.mlf";

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): generating Page XML with alignments ..." 1>&2;

  local ff=$(sed -n '/\.rec"$/{ s|.*/||; s|\.rec"||; p; }' "$TMPDIR/${FN}_aligned.mlf");

  local align=$(
      sed -n '
        /\/'${ff}'\.rec"$/{
          :loop;
          N;
          /\n\.$/!b loop;
          s|^[^\n]*\n||;
          s|\n\.$||;
          #s|<dquote>|{dquote}|g;
          #s|<quote>|{quote}|g;
          #s|<GAP>|{GAP}|g;
          #s|&|&amp;|g;
          p; q;
        }' "$TMPDIR/${FN}_aligned.mlf" \
        | awk '
            { $1 = $1==0 ? 0 : $1/100000-1 ;
              $2 = $2/100000-1 ;
              NF = 3;
              print;
            }'
      );

  local size=$(xmlstarlet sel -t -v //@imageWidth -o x -v //@imageHeight "$XML");
  local fbox=$(xmlstarlet sel -t -m '//_:TextLine/_:Coords/@fpgram' -v . -n "$XML" \
                 | sed 's| |,|g; $!s|$|;|;' | tr -d '\n');
  local frames=$(sed 's|.* ||;' "$NFRAMES" | tr '\n' ',' | sed 's|,$||');
  local a=$(echo "$align" | sed 's|^[^ ]* ||; s| .*||; $!s|$|,|;' | tr -d '\n');

  ### Get parallelogram coordinates of alignments ###
  align=$(
      echo "
        fbox = [ $fbox ];

        frames = [ $frames ];
        cframes = cumsum(frames)-1;
        cframes = [ 0 cframes(1:end-1); cframes ]';

        a = [ $a ];
        a = [ 0 a(1:end-1); a ]';

        K = size(a,1);
        coords = zeros(K,8);

        N = length(frames);
        frame = zeros(N,1);

        for n = 1:N
          sel = sum( a>=cframes(n,1) & a<=cframes(n,2), 2 );
          for m = find(sel==1)'
            if a(m,1) < cframes(n,1) && a(m,2)-cframes(n,1) >= cframes(n,1)-a(m,2)
              sel(m) = 2;
            elseif a(m,2) > cframes(n,2) && cframes(n,2)-a(m,1) >= a(m,2)-cframes(n,2)
              sel(m) = 2;
            end
          end
          sel = sel == 2;
          frame(sel) = n;

          dx = ( fbox(n,3)-fbox(n,1) ) / ( frames(n)-1 ) ;
          dy = ( fbox(n,4)-fbox(n,2) ) / ( frames(n)-1 ) ;

          xup = round( fbox(n,1) + dx*(a(sel,:)-cframes(n,1)) );
          yup = round( fbox(n,2) + dy*(a(sel,:)-cframes(n,1)) );
          xdown = round( fbox(n,7) + dx*(a(sel,:)-cframes(n,1)) );
          ydown = round( fbox(n,8) + dy*(a(sel,:)-cframes(n,1)) );

          coords(sel,:) = [ xdown(:,1) ydown(:,1) xup(:,1) yup(:,1) xup(:,2) yup(:,2) xdown(:,2) ydown(:,2) ];
        end

        for k = 1:K
          printf('%d %d,%d %d,%d %d,%d %d,%d\n',
            frame(k),
            coords(k,1), coords(k,2),
            coords(k,3), coords(k,4),
            coords(k,5), coords(k,6),
            coords(k,7), coords(k,8) );
        end" \
      | octave -q \
      | paste -d " " - <( echo "$align" | awk '{print $NF}' )
    );

  ### Prepare command to add alignments to XML ###
  local cmd="xmlstarlet ed -P -d //_:Word -d //_:Glyph";

  local id contour;
  local l="0";

  ### Loop through words ###
  local W=$(echo "$align" | grep ' @$' | wc -l); W=$((W-1));
  local w;
  for w in $(seq 1 $W); do
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): alignments for word $w ..." 1>&2;
    local ww=$(printf %.3d $w);
    local pS=$(echo "$align" | grep -n ' @$' | sed -n "$w{s|:.*||;p;}"); pS=$((pS+1));
    local pF=$(echo "$align" | grep -n ' @$' | sed -n "$((w+1)){s|:.*||;p;}"); pF=$((pF-1));

    a=$(echo "$align" | sed -n "$pS,$pF{s| .*||;p;}");
    local ll=$(echo "$a" | head -n 1);
    local pE=$(( pS - 1 + $(echo "$a" | sed -n "/^${ll}$/=" | tail -n 1) ));

    if [ "$l" != "$ll" ]; then
      l="$ll";
      id=$(xmlstarlet sel -t -m "(//_:TextLine/_:Coords[@fpgram])[$l]" -v ../@id "$XML");
      [ "$htrsh_align_isect" = "yes" ] &&
        contour=$(xmlstarlet sel -t -v "//*[@id=\"${id}\"]/_:Coords/@points" "$XML");
    fi

    ### Word level alignments (left part if divided) ###
    local g=1;

    word_and_char_align () {
      if [ "$pS" = "$pE" ]; then
        pts=$(echo "$align" | sed -n "$pS{ s|^[^ ]* ||; s| [^ ]*$||; p; q; }");
      else
        pts=$(echo "$align" \
          | sed -n "
              s|^[^ ]* ||;
              s| [^ ]*$||;
              $pS{ s| [^ ]* [^ ]*$||; p; };
              $pE{ s|^[^ ]* [^ ]* ||; p; q; };" \
          | tr '\n' ' ' \
          | sed 's| $||');
      fi

      if [ "$htrsh_align_isect" = "yes" ]; then
        local pts2=$(
          convert -fill white -stroke white \
              \( -size $size xc:black -draw "polyline $contour" \) \
              \( -size $size xc:black -draw "polyline $pts" \) \
              -compose Darken -composite -trim png:- \
            | imgccomp -V0 -JS - );
        [ "$pts2" != "" ] && pts="$pts2";
      fi

      cmd="$cmd -s '//*[@id=\"${id}\"]' -t elem -n TMPNODE";
      cmd="$cmd -i '//TMPNODE' -t attr -n id -v '${id}_w${ww}'";
      cmd="$cmd -s '//TMPNODE' -t elem -n Coords";
      cmd="$cmd -i '//TMPNODE/Coords' -t attr -n points -v '$pts'";
      cmd="$cmd -r '//TMPNODE' -v Word";

      ### Character level alignments ###
      if [ "$htrsh_align_chars" = "yes" ]; then
        local c;
        for c in $(seq $pS $pE); do
          local gg=$(printf %.2d $g);
          local pts=$(echo "$align" | sed -n "$c{ s|^[^ ]* ||; s| [^ ]*$||; p; q; }");
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

      local text=$(echo "$align" | sed -n "$pS,$pE{s|.* ||;p;}" | tr -d '\n');

      cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]' -t elem -n TextEquiv";
      cmd="$cmd -s '//*[@id=\"${id}_w${ww}\"]/TextEquiv' -t elem -n Unicode -v '$text'";
    }
    word_and_char_align;

    ### Check if word spans multiple lines ###
    local L=$(echo "$a" | sort -u | wc -l);
    [ "$L" -gt 2 ] &&
      echo "$FN: error: word spans more than 2 lines, this possibility not considered yet: $XML" 1>&2 &&
      return 1;

    ### Word spans two lines ###
    if [ "$L" = 2 ]; then
      l=$(echo "$a" | sort -u | sed -n 2p);
      id=$(xmlstarlet sel -t -m "(//_:TextLine/_:Coords[@fpgram])[$l]" -v ../@id "$XML");
      [ "$htrsh_align_isect" = "yes" ] &&
        contour=$(xmlstarlet sel -t -v "//*[@id=\"${id}\"]/_:Coords/@points" "$XML");

      ### Word level alignments (right part) ###
      pS=$(( pE + 1 ));
      pE="$pF";
      word_and_char_align;
    fi

  done # Word loop

  unset -f word_and_char_align;

  local L="$l";
  for l in $(seq 1 $L); do
    id=$(xmlstarlet sel -t -m "(//_:TextLine/_:Coords[@fpgram])[$l]" -v ../@id "$XML");

    local text=$(echo "$align" | sed -n "/^${l} /{ s|.* ||; s|@| |; p; }" | tr -d '\n' | sed 's|^ ||; s| $||;');

    cmd="$cmd -d '//*[@id=\"${id}\"]/_:TextEquiv'";
    cmd="$cmd -s '//*[@id=\"${id}\"]' -t elem -n TextEquiv";
    cmd="$cmd -s '//*[@id=\"${id}\"]/TextEquiv' -t elem -n Unicode -v '$text'";
  done

  ### Create new XML including alignments ###
  eval $cmd "$XML" > "$XMLOUT";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating XML file: $XMLOUT" 1>&2 &&
    return 1;

  htrsh_fix_rec_names "$XMLOUT";

  [ "$htrsh_keeptmp" -lt 1 ] &&
    rm -f "$TMPDIR/$FN.mlf" "$TMPDIR/${FN}_aligned.mlf";

  return 0;
}

##
## Function that does a forced alignment given only a page with baselines and optionally a model
##
htrsh_pageimg_forcealign () {
  local FN="htrsh_pageimg_forcealign";
  local TS=$(date +%s);
  local TMPDIR="./_forcealign";
  local INRES="";
  local MODEL="";
  local PBASE="";
  local DOPCA="yes";
  local KEEPTMP="no";
  local KEEPAUX="no";
  local QBORD="no";
  if [ $# -lt 2 ]; then
    { echo "$FN: error: not enough input arguments";
      echo "Usage: $FN XMLIN XMLOUT [ OPTIONS ]";
      echo "Options:";
      echo " -d TMPDIR    Directory for temporary files (def.=$TMPDIR)";
      echo " -i INRES     Input image resolution in ppc (def.=use image metadata)";
      echo " -m MODEL     Use model for aligning (def.=train model for page)";
      echo " -b PBASE     Project features using given base (def.=false)";
      echo " -p (yes|no)  Whether to compute PCA for image and project features (def.=$DOPCA)";
      echo " -t (yes|no)  Whether to keep temporary directory and files (def.=$KEEPTMP)";
      echo " -a (yes|no)  Whether to keep auxiliary attributes in XML (def.=$KEEPAUX)";
      echo " -q (yes|no)  Whether to clean quadrilateral border of regions (def.=$QBORD)";
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
    elif [ "$1" = "-i" ]; then
      INRES="$2";
    elif [ "$1" = "-m" ]; then
      MODEL="$2";
    elif [ "$1" = "-b" ]; then
      PBASE="$2";
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
    if [ "${RMTMP:0:1}" = "yes" ]; then
      rm -r "$TMPDIR";
    else
      echo "$FN: aborting ..." 1>&2;
      return 1;
    fi
  fi

  ### Check page ###
  htrsh_pageimg_info "$XML" noinfo;
  [ "$?" != 0 ] && return 1;

  local RCNT=$(xmlstarlet sel -t -v 'count(//*[@type="paragraph"]/_:TextEquiv/_:Unicode)' "$XML");
  local LCNT=$(xmlstarlet sel -t -v 'count(//*[@type="paragraph"]/_:TextLine/_:TextEquiv/_:Unicode)' "$XML");
  [ "$RCNT" = 0 ] && [ "$LCNT" = 0 ] &&
    echo "$FN: error: no TextEquiv/Unicode nodes for processing: $XML" 1>&2 &&
    return 1;

  local WGCNT=$(xmlstarlet sel -t -v 'count(//_:Word)' -o ' ' -v 'count(//_:Glyph)' "$XML");
  [ "$WGCNT" != "0 0" ] &&
    echo "$FN: warning: input already contains Word and/or Glyph information: $XML" 1>&2;

  local AREG="no"; [ "$LCNT" = 0 ] && AREG="yes";

  mkdir -p "$TMPDIR";

  local I=$(xmlstarlet sel -t -v //@imageFilename "$XML");
  local B=$(echo "$XML" | sed 's|.*/||; s|\.[^.]*$||;');

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): processing page: $XML";

  ### Clean page image ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): enhancing page image ...";
  [ "$INRES" != "" ] && INRES="-i $INRES";
  htrsh_pageimg_clean "$XML" "$TMPDIR" $INRES \
    > "$TMPDIR/${B}_pageclean.log";
  [ "$?" != 0 ] && return 1;

  ### Clean quadrilateral borders ###
  if [ "$QBORD" = "yes" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): cleaning quadrilateral borders ...";
    local II=$(echo $I | sed 's|.*/||; s|\.[^.]*$||');
    htrsh_pageimg_quadborderclean "$TMPDIR/${B}.xml" "$TMPDIR/${II}_nobord.png" -d "$TMPDIR";
    [ "$?" != 0 ] && return 1;
    mv "$TMPDIR/${II}_nobord.png" "$TMPDIR/${II}.png";
  fi

  ### Generate contours from baselines ###
  if [ $(xmlstarlet sel -t -v 'count(//*[@type="paragraph"]/_:TextLine/_:Coords[@points and @points!="0,0 0,0"])' "$TMPDIR/$B.xml") = 0 ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): generating line contours from baselines ...";
    page_format_generate_contour -a 75 -d 25 -p "$TMPDIR/$B.xml" -o "$TMPDIR/${B}_contours.xml";
    [ "$?" != 0 ] &&
      echo "$FN: error: page_format_generate_contour failed" 1>&2 &&
      return 1;
  else
    mv "$TMPDIR/$B.xml" "$TMPDIR/${B}_contours.xml";
  fi

  ### Extract line features ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): extracting line features ...";
  htrsh_pageimg_extract_linefeats \
    "$TMPDIR/${B}_contours.xml" "$TMPDIR/${B}_feats.xml" \
    -d "$TMPDIR" -l "$TMPDIR/${B}_feats.lst" \
    > "$TMPDIR/${B}_linefeats.log";
  [ "$?" != 0 ] && return 1;

  ### Compute PCA and project features ###
  if [ "$DOPCA" = "yes" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): computing PCA for page ...";
    PBASE="$TMPDIR/pcab.mat.gz";
    htrsh_feats_pca "$TMPDIR/${B}_feats.lst" "$PBASE" -e "1:4" -r 24 -d "$TMPDIR";
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

  ### Concatenate line features to align whole region ###
  if [ "$AREG" = "yes" ]; then
    gunzip $TMPDIR/*.fea.gz;
    local fea=$(head -n 1 $TMPDIR/${B}_feats.lst | sed 's|[^.]*\.fea|fea|');
    for f in $(cat $TMPDIR/${B}_feats.lst); do
      HList -r $f;
    done > ${fea}~;
    for f in $(cat $TMPDIR/${B}_feats.lst); do
      echo $f | sed 's|.*/[^.]*\.[^.]*\.||; s|\.fea||' | tr '\n' ' ';
      HList -h -z $f | sed -n '/Num Samples:/{ s|.*Num Samples: *||; s| .*||; p; }';
    done > $TMPDIR/${B}_numframes.lst;

    pfl2htk ${fea}~ ${fea} 2>/dev/null;
    gzip ${fea};
    rm $TMPDIR/*.fea ${fea}~;
    echo "$fea" > $TMPDIR/${B}_feats.lst;
  fi

  ### Train HMMs model for this single page ###
  if [ "$MODEL" = "" ]; then
    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): training model for page ...";
    htrsh_page_to_mlf "$TMPDIR/${B}_feats.xml" -r $AREG > "$TMPDIR/${B}_page.mlf";
    [ "$?" != 0 ] && return 1;
    htrsh_hmm_train \
      "$TMPDIR/${B}_feats.lst" "$TMPDIR/${B}_page.mlf" -d "$TMPDIR" \
      > "$TMPDIR/${B}_hmmtrain.log";
    [ "$?" != 0 ] && return 1;
    MODEL="$TMPDIR/Macros_hmm_g$(printf %.3d $htrsh_hmm_nummix).gz";
  fi
  [ ! -e "$MODEL" ] &&
    echo "$FN: error: model file not found: $MODEL" 1>&2 &&
    return 1;

  ### Do forced alignment using model ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): doing forced alignment ...";
  if [ "$AREG" = "yes" ]; then
    # @todo how to handle multiple regions
    htrsh_pageimg_forcealign_regions \
      "$TMPDIR/${B}_feats.xml" "$TMPDIR/${B}_feats.lst" "$TMPDIR/${B}_numframes.lst" "$MODEL" \
      "$XMLOUT" -d "$TMPDIR" \
      > "$TMPDIR/${B}_forcealign.log";
    [ "$?" != 0 ] && return 1;
  else
    htrsh_pageimg_forcealign_lines \
      "$TMPDIR/${B}_feats.xml" "$TMPDIR/${B}_feats.lst" "$MODEL" \
      "$XMLOUT" -d "$TMPDIR" \
      > "$TMPDIR/${B}_forcealign.log";
    [ "$?" != 0 ] && return 1;
  fi 2>&1;

  [ "$KEEPTMP" != "yes" ] && rm -r "$TMPDIR";

  local ed="-u //@imageFilename -v '$I'";
  [ "$KEEPAUX" != "yes" ] && ed="$ed -d //@fpgram -d //@fcontour";

  eval xmlstarlet ed --inplace $ed "$XMLOUT";

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): finished, $(( $(date +%s)-TS )) seconds";

  return 0;
}
