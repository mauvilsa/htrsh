#!/bin/bash

htrsh_align_wordsplit="no"; # Whether to split words when aligning regions
#htrsh_align_words="no"; # Whether to align at a word level when aligning regions

htrsh_hmm_software="kaldi";

#htrsh_hmm_iter="10";
htrsh_keeptmp="1";
#htrsh_imglineclean_opts="-m 99% -b 0";
#htrsh_imgtxtenh_opts="-r 0.16 -w 20 -k 0.5"; #htrsh_align_isect="no"; # Alc
#htrsh_imgtxtenh_opts="-r 0.16 -w 20 -k 0.2"; # Zwettl

#htrsh_feat_deslant="no";

htrsh_pagexsd="/home/mvillegas/work/prog/mvsh/HTR/xsd/pagecontent+.xsd";

htrsh_feat_contour=$htrsh_align_isect;


#-------------------------------------#
# Viterbi alignment related functions #
#-------------------------------------#

##
## Function that does a forced alignment for a region given an XML Page file, model and directory to find the features
##
htrsh_pageimg_forcealign_region () {
  local FN="htrsh_pageimg_forcealign_region";
  local TMPDIR=".";
  if [ $# -lt 5 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Does a forced alignment for a region given an XML Page file, model and directory to find the features";
      echo "Usage: $FN XMLIN REGID FEATDIR MODEL XMLOUT [ Options ]";
      echo "Options:";
      echo " -d TMPDIR    Directory for temporary files (def.=$TMPDIR)";
    } 1>&2;
    return 1;
  fi

  ### Parse input agruments ###
  local XML="$1";
  local REGID="$2";
  local FEATDIR="$3";
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

  #if ! [ -e "$MODEL" ]; then
  #  echo "$FN: error: model file not found: $MODEL" 1>&2;
  #  return 1;
  #fi

  ### Check page and obtain basic info ###
  local XMLDIR IMFILE IMSIZE IMRES;
  htrsh_pageimg_info "$XML";
  [ "$?" != 0 ] && return 1;

  local FBASE="$FEATDIR/"$(echo "$IMFILE" | sed 's|.*/||; s|\.[^.]*$||;');

  local FEATLST=$(
    { echo "$FBASE.$REGID.fea";
      xmlstarlet sel -t -m "//*[@id=\"$REGID\"]/_:TextLine/_:Coords" \
        -o "$FBASE." -v ../../@id -o "." -v ../@id -o ".fea" -n "$XML";
    } | xargs ls
    );
  [ "$?" != 0 ] &&
    echo "$FN: error: some features files not found" 1>&2 &&
    return 1;

  local f;
  local NFRAMES=$(
    for f in $(xmlstarlet sel -t -m "//*[@id=\"$REGID\"]/_:TextLine/_:Coords" -o "$FBASE." -v ../../@id -o "." -v ../@id -o ".fea" -n "$XML"); do
      echo $f | sed 's|.*/[^.]*\.[^.]*\.||; s|\.fea||' | tr '\n' ' ';
      HList -h -z $f | sed -n '/Num Samples:/{ s|.*Num Samples: *||; s| .*||; p; }';
    done
    );

  local XMLBASE=$(echo "$XML" | sed 's|.*/||;s|\.xml$||;');

  ### Create MLF from XML ###
  if [ "$htrsh_hmm_software" = "htk" ]; then

  if [ ! -e "$MODEL" ]; then
    echo "$FN: error: model file not found: $MODEL" 1>&2;
    return 1;
  fi

  htrsh_pagexml_to_mlf "$XML" -r yes > "$TMPDIR/$XMLBASE.mlf";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating MLF file: $XML" 1>&2 &&
    return 1;

  ### Create auxiliary files: HMM list and dictionary ###
  local HMMLST=$(zcat "$MODEL" | sed -n '/^~h "/{ s|^~h "||; s|"$||; p; }');
  local DIC=$(echo "$HMMLST" | awk '{printf("\"%s\" [%s] 1.0 %s\n",$1,$1,$1)}');

  ### Do forced alignment with HVite ###
  echo "$FBASE.$REGID.fea" > "$TMPDIR/fea.lst";
  HVite $htrsh_HTK_HVite_opts -C <( echo "$htrsh_baseHTKcfg" ) -H "$MODEL" -S "$TMPDIR/fea.lst" -m -I "$TMPDIR/$XMLBASE.mlf" -i "$TMPDIR/${XMLBASE}_aligned.mlf" <( echo "$DIC" ) <( echo "$HMMLST" );
  [ "$?" != 0 ] &&
    echo "$FN: error: problems aligning with HVite: $XML" 1>&2 &&
    return 1;

  #htrsh_fix_rec_utf8 "$MODEL" "$TMPDIR/${XMLBASE}_aligned.mlf";


  elif [ "$htrsh_hmm_software" = "kaldi" ]; then

    local REPLACE=$(echo "$MODEL" | awk -F: '{print $5}');
    local CHARIDS=$(echo "$MODEL" | awk -F: '{print $4}');
    local WORDIDS=$(echo "$MODEL" | awk -F: '{print $3}');
    local FSTS=$(echo "$MODEL" | awk -F: '{print $2}');
    MODEL=$(echo "$MODEL" | awk -F: '{print $1}');

    if [ ! -e "$MODEL" ]; then
      echo "$FN: error: model file not found: $MODEL" 1>&2;
      return 1;
    elif [ ! -e "$FSTS" ]; then
      echo "$FN: error: transcription FST not found: $FSTS" 1>&2;
      return 1;
    elif [ ! -e "$WORDIDS" ]; then
      echo "$FN: error: word identifier list not found: $WORDIDS" 1>&2;
      return 1;
    elif [ ! -e "$CHARIDS" ]; then
      echo "$FN: error: character identifier list not found: $WORDIDS" 1>&2;
      return 1;
    elif [ "$REPLACE" != "" ] && [ ! -e "$REPLACE" ]; then
      echo "$FN: error: replacement list not found: $REPLACE" 1>&2;
      return 1;
    fi

    if [ $(file "$FSTS" | grep gzip | wc -l) = 0 ]; then
      FSTS="ark:$FSTS";
    else
      FSTS="ark:zcat $FSTS |";
    fi

    ls "$FEATDIR/$XMLBASE.$REGID.fea" \
      | htrsh_feats_htk_to_kaldi "$TMPDIR/${XMLBASE//,/-}.$REGID" 2>/dev/null;

    local ALIGN=$(
       gmm-align-compiled+ --write-outlabels --transition-scale=1.0 --acoustic-scale=0.1 --self-loop-scale=0.1 --beam=1000 --retry-beam=2000 "$MODEL" "$FSTS" "scp:$TMPDIR/${XMLBASE//,/-}.$REGID.scp" ark,t:- 2>/dev/null
       );

    if [ "$?" != 0 ] || [ "$ALIGN" = "" ]; then
      echo "$FN: error: problems aligning with gmm-align-compiled+: $XML" 1>&2;
      return 1;
    fi

    rm "$TMPDIR/${XMLBASE//,/-}.$REGID".{ark,scp};

    { echo "$ALIGN" \
        | awk '
            { w = 0;
              for( n=3; n<NF; n+=3 )
                if( $n != 0 ) {
                  printf( "%s%d %d", w==0?"":" ", $n, (n/3)-1 );
                  w ++;
                }
              printf( "\n" );
            }';
      echo "$ALIGN" \
        | sed 's|[0-9]\{1,\} ; ||g; s| [0-9]\{1,\} *$||;' \
        | ali-to-phones --write-lengths "$MODEL" ark:- ark,t:- 2>/dev/null \
        | sed 's|^[^ ]* ||; s| ;||g; s|  *$||;';
    } | awk '
          BEGIN {
            print( "#!MLF!#" );
            print( "\"*/'"$XMLBASE.$REGID"'.rec\"" );
          }
          { if( FILENAME == "'"$WORDIDS"'" )
              words[$2] = $1;
            else if( FILENAME == "'"$CHARIDS"'" )
              chars[$2] = $1;
            else if( FILENAME == "'"$REPLACE"'" )
              replc[( $2 "|" $3 )] = $1;
            else {
              if( FNR == 1 ) {
                NWORDS = NF/2;
                for( n=1; n<NF; n+=2 ) {
                  word[(n+1)/2] = words[$n];
                  wordpos[(n+1)/2] = $(n+1);
                }
              }
              else {
                f = 0;
                w = 1;
                c = 1;
                while( c < NF ) {
                  if( chars[$c] != "0x20" )
                    printf( "%d %d @\n", f, f );
                  else {
                    printf( "%d %d @\n", f, f+$(c+1)-1 );
                    f += $(c+1);
                    c += 2;
                    if( c > NF )
                      break;
                  }
                  if( f != wordpos[w] ) {
                    printf("error: expected word %d in frame %d but reached this point in frame %d\n",word[w],wordpos[w],f) > "/dev/stderr";
                    exit 1;
                  }
                  printf( "%d", f );
                  ww = "";
                  while( c < NF && 
                         chars[$c] != "0x20" &&
                         ( w == NWORDS || f < wordpos[w+1] ) ) {
                    ww = ( ww chars[$c] );
                    f += $(c+1);
                    c += 2;
                  }
                  printf( " %d", f-1 );
                  if( ww != word[w] ) {
                    if( ( ww "|" word[w] ) in replc )
                      ww = replc[( ww "|" word[w] )];
                    else {
                      ww1 = gensub( /[.,:;?\x27\x22-]*([^.,:;?\x27\x22-]+)[.,:;?\x27\x22-]*/, "\\1", "", word[w] );
                      ww2 = gensub( /[.,:;?\x27\x22-]*([^.,:;?\x27\x22-]+)[.,:;?\x27\x22-]*/, "\\1", "", ww );
                      #printf("abbrev: %s => %s (%s => %s)\n",word[w],ww,ww1,ww2) > "/dev/stderr";
                      if( ( ww2 "|" ww1 ) in replc )
                      ww = gensub( ("([.,:;?\x27\x22-]*)" ww2 "([.,:;?\x27\x22-]*)"), ("\\1" replc[( ww2 "|" ww1 )] "\\2"), "", ww );
                    }
                    ww = ( ww "$." word[w] );
                  }
                  printf( " %s\n", ww );
                  w += 1;
                }
                if( w <= NWORDS ) {
                  printf("error: more words than consumed characters\n") > "/dev/stderr";
                  exit 1;
                }
                if( chars[$(NF-1)] != "0x20" )
                  printf( "%d %d @\n", f-1, f-1 );
              }
            }
          }
          END {
            print( "." );
          }
          ' "$WORDIDS" "$CHARIDS" "$REPLACE" - \
      | awk '{if(NF==3){$1=100000*$1;$2=100000*$2;}print;}' \
      | sed '
          /^"/!s|"|{dquote}|g;
          s|'"'"'|{quote}|g;
          ' \
      > "$TMPDIR/${XMLBASE}_aligned.mlf";

    #sed -n '1p; /\/'$XMLBASE.$REGID'.rec"$/{ :loop; N; /\n\.$/!b loop; p; };' align.mlf \
    #  | awk '{if(NF==3){$1=100000*$1;$2=100000*$2;}print;}' \
    #  | sed "s|'|{quote}|g" \
    #  > "$TMPDIR/${XMLBASE}_aligned.mlf";


if false; then

awk '{printf("%s #1\n",$0)}' kaldi/train/local/dict/lexiconp.txt > kaldi/train/local/dict/lexiconp+.txt;

phone_disambig_symbol=$(grep \#0 kaldi/train/lang/phones.txt | awk '{print $2}');
utils/make_lexicon_fst.pl \
    --pron-probs kaldi/train/local/dict/lexiconp+.txt 0.5 0x20 '#1' \
  | fstcompile \
      --isymbols=kaldi/train/lang/phones.txt \
      --osymbols=kaldi/train/lang/words.txt \
      --keep_isymbols=false --keep_osymbols=false \
  | fstarcsort --sort_type=olabel \
  > kaldi/train/lang/L+.fst #|| exit 1;
#  | fstaddselfloops \
#    "echo $phone_disambig_symbol |" "echo |" \

grep ^$XMLBASE.$REGID kaldi/train/text > kaldi/train/text+;

compile-train-graphs kaldi/ns6/tree kaldi/ns6/gmm_7872/it_4/mdl kaldi/train/lang/L+.fst \
    "ark:utils/sym2int.pl -f 2- kaldi/train/lang/words.txt < kaldi/train/text+ |" \
    "ark:| gzip -c > kaldi/ns6/fsts+.gz" #|| exit 1;


    { echo "$ALIGN" \
        | awk '
            { w = 0;
              for( n=3; n<NF; n+=3 )
                if( $n != 0 ) {
                  printf( "%s%d %d", w==0?"":" ", $n, (n/3)-1 );
                  w ++;
                }
              printf( "\n" );
            }';
      echo "$ALIGN" \
        | sed 's|[0-9]\{1,\} ; ||g; s| [0-9]\{1,\} *$||;' \
        | ali-to-phones --write-lengths "$MODEL" ark:- ark,t:- 2>/dev/null \
        | sed 's|^[^ ]* ||; s| ;||g; s|  *$||;';
    } | awk '
          { if( FILENAME == "'"$WORDIDS"'" )
              words[$2] = $1;
            else if( FILENAME == "'"$CHARIDS"'" )
              chars[$2] = $1;
            else {
              if( FNR == 1 ) {
                for( n=1; n<NF; n+=2 )
                  word[$(n+1)] = words[$n];
              }
              else {
                f = 0;
                for( c=1; c<NF; c+=2 ) {
                  if( f in word )
                    printf( "%s : %s\n", chars[$c], word[f] );
                  else
                    printf( "%s : %s\n", chars[$c], "<eps>" );
                    f += $(c+1);
                }
              }
            }
          }
          ' "$WORDIDS" "$CHARIDS" - | less


fi


  fi

  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): generating Page XML with alignments ..." 1>&2;

  local ff=$(sed -n '/\.rec"$/{ s|.*/||; s|\.rec"||; p; }' "$TMPDIR/${XMLBASE}_aligned.mlf");

  local align=$(
      sed -n '
        /\/'${ff}'\.rec"$/{
          :loop;
          N;
          /\n\.$/!b loop;
          s|^[^\n]*\n||;
          s|\n\.$||;
          p; q;
        }' "$TMPDIR/${XMLBASE}_aligned.mlf" \
        | awk '
            { $1 = $1==0 ? 0 : $1/100000-1 ;
              $2 = $2/100000-1 ;
              NF = 3;
              print;
            }'
      );

  #echo "$align" > "$TMPDIR/var_align0.txt";

  local size=$(xmlstarlet sel -t -v //@imageWidth -o x -v //@imageHeight "$XML");
  local fbox=$(xmlstarlet sel -t -m "//*[@id=\"$REGID\"]/_:TextLine/_:Coords/@fpgram" -v . -n "$XML" \
                 | sed 's| |,|g; $!s|$|;|;' | tr -d '\n');
  local frames=$(sed 's|.* ||;' <( echo "$NFRAMES" ) | tr '\n' ',' | sed 's|,$||');
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
            if a(m,1) < cframes(n,1) && a(m,2)-cframes(n,1) >= cframes(n,1)-a(m,1)
              sel(m) = 2;
            elseif a(m,2) > cframes(n,2) && cframes(n,2)-a(m,1) >= a(m,2)-cframes(n,2)
              sel(m) = 2;
            end
          end
          sel = sel == 2;
          frame(sel) = n;

          dx = ( fbox(n,3)-fbox(n,1) ) / ( frames(n)-1 ) ;
          dy = ( fbox(n,4)-fbox(n,2) ) / ( frames(n)-1 ) ;

          aa = a(sel,:);
          aa(aa<cframes(n,1)) = cframes(n,1);
          aa(aa>cframes(n,2)) = cframes(n,2);
          aa = aa-cframes(n,1);

          xup = round( fbox(n,1) + dx*aa );
          yup = round( fbox(n,2) + dy*aa );
          xdown = round( fbox(n,7) + dx*aa );
          ydown = round( fbox(n,8) + dy*aa );

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
      #| tee "$TMPDIR/var_align.m" \
    );

  #echo "$align" > "$TMPDIR/var_align.txt";

  if [ "$htrsh_align_wordsplit" != "yes" ]; then
    #mv "$TMPDIR/var_align.txt" "$TMPDIR/var_align1.txt";

    align=$(
      echo "$align" \
        | awk '
            { ln[NR] = $1;
              pgram[NR] = ( $2 " " $3 " " $4 " " $5 );
              txt[NR] = $6;
            }
            END {
              for( n=2; n<=NR; n++ )
                if( ( ln[n] != ln[n-1] ) &&
                    ! ( txt[n]=="@" || txt[n-1]=="@" ) ) {
                  pS = n-1; while( pS > 1  && txt[pS-1] != "@" ) pS --;
                  pF = n-1; while( pF < NR && txt[pF+1] != "@" ) pF ++;
                  if( n - pS >= pF - n + 1 )
                    for( m=n; m<=pF; m++ ) {
                      ln[m] = ln[n-1];
                      pgram[m] = pgram[n-1];
                    }
                  else
                    for( m=pS; m<=n-1; m++ ) {
                      ln[m] = ln[n];
                      pgram[m] = pgram[n];
                    }
                }

              for( n=1; n<=NR; n++ )
                printf("%s %s %s\n",ln[n],pgram[n],txt[n]);
            }'
      );

    #echo "$align" > "$TMPDIR/var_align.txt";
  fi

  ### Prepare command to add alignments to XML ###
  local cmd="xmlstarlet ed";
  cmd="$cmd -d '//*[@id=\"$REGID\"]/*/_:Word' -d '//*[@id=\"$REGID\"]/*/_:Glyph'";

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
      id=$(xmlstarlet sel -t -m "(//*[@id=\"$REGID\"]/_:TextLine/_:Coords[@fpgram])[$l]" -v ../@id "$XML");
      [ "$htrsh_align_isect" = "yes" ] &&
        contour=$(xmlstarlet sel -t -v "//*[@id=\"$id\"]/_:Coords/@points" "$XML");
    fi

    ### Word level alignments (left part if divided) ###
    local g=1;

    word_and_char_align () {
      if [ "$htrsh_align_words" = "yes" ]; then

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
        [ "$pts2" != "" ] && pts="$pts2";
      fi

      cmd="$cmd -s '//*[@id=\"$id\"]' -t elem -n TMPNODE";
      cmd="$cmd -i '//TMPNODE' -t attr -n id -v '${id}_w${ww}'";
      cmd="$cmd -s '//TMPNODE' -t elem -n Coords";
      cmd="$cmd -i '//TMPNODE/Coords' -t attr -n points -v '$pts'";
      cmd="$cmd -r '//TMPNODE' -v Word";

      fi

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
      echo "$FN: error: word spans more than $L lines, this possibility not considered yet: $XML" 1>&2 &&
      return 1;
      #echo "$a" >> "$TMPDIR/var_a.txt" &&

    ### Word spans two lines ###
    if [ "$L" = 2 ]; then
      l=$(echo "$a" | sort -nu | sed -n 2p);
      id=$(xmlstarlet sel -t -m "(//*[@id=\"$REGID\"]/_:TextLine/_:Coords[@fpgram])[$l]" -v ../@id "$XML");
      [ "$htrsh_align_isect" = "yes" ] &&
        contour=$(xmlstarlet sel -t -v "//*[@id=\"$id\"]/_:Coords/@points" "$XML");

      ### Word level alignments (right part) ###
      pS=$(( pE + 1 ));
      pE="$pF";
      word_and_char_align;
    fi

  done # Word loop

  unset -f word_and_char_align;

  local L="$l";
  for l in $(seq 1 $L); do
    id=$(xmlstarlet sel -t -m "(//*[@id=\"$REGID\"]/_:TextLine/_:Coords[@fpgram])[$l]" -v ../@id "$XML");

    local text=$(echo "$align" | sed -n "/^$l /{ s|.* ||; s|@| |; p; }" | tr -d '\n' | sed 's|^ ||; s| $||;');

    cmd="$cmd -d '//*[@id=\"$id\"]/_:TextEquiv'";
    cmd="$cmd -s '//*[@id=\"$id\"]' -t elem -n TextEquiv";
    cmd="$cmd -s '//*[@id=\"$id\"]/TextEquiv' -t elem -n Unicode -v '$text'";
  done

  ### Create new XML including alignments ###
  #echo eval $cmd "$XML" > "$TMPDIR/var_cmd.txt";
  eval $cmd "$XML" > "$XMLOUT";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating XML file: $XMLOUT" 1>&2 &&
    return 1;

  htrsh_fix_rec_names "$XMLOUT";

  [ "$htrsh_keeptmp" -lt 1 ] &&
    rm -f "$TMPDIR/$XMLBASE.mlf" "$TMPDIR/${XMLBASE}_aligned.mlf";

  return 0;
}
