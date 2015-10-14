

htrsh_kaldi_mixfact="2";       # Gaussian mixtures incrementing factor
htrsh_kaldi_gmmest_opts=(
  "--min-gaussian-occupancy=3"
  "--power=0.2");              # Options for gmm-est tool
htrsh_kaldi_gmmalign_opts="
  --print-args=false
  --transition-scale=1.0
  --acoustic-scale=0.1
  --self-loop-scale=0.1
  --beam=1000
  --retry-beam=2000";          # Options for gmm-align-compiled tool
htrsh_kaldi_gmmfb_opts="
  --print-args=false
  --transition-scale=1.0
  --acoustic-scale=0.1
  --self-loop-scale=0.1";      # Options for gmm-fb-compiled tool



##
## Function that trains HMMs for a given feature table and text table using kaldi
##
# @todo input should be FEATLST TEXTTAB and LEXICON
# @todo save all model files in a single package with manifest.xml including: md5sums, how feat extract, how train, etc.
htrsh_hmm_train_kaldi () {
  local FN="htrsh_hmm_train_kaldi";
  local OUTDIR=".";
  #local PROTO="";
  local FB="no";
  local KEEPITERS="yes";
  local KEEPMISC="no";
  local RESUME="yes";
  local THREADS="1";
  if [ $# -lt 2 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Trains HMMs for a given feature list and mlf";
      echo "Usage: $FN FEATLST TEXTTAB [ Options ]";
      echo "Options:";
      echo " -d OUTDIR    Directory for output models and temporary files (def.=$OUTDIR)";
      #echo " -P PROTO     Use PROTO as initialization prototype (def.=false)";
      echo " -fb (yes|no) Whether to train using forward-backwards instead of viterbi (def.=$FB)";
      echo " -k (yes|no)  Whether to keep models per iteration, including initialization (def.=$KEEPITERS)";
      echo " -m (yes|no)  Whether to keep features table and train graphs (def.=$KEEPMISC)";
      echo " -r (yes|no)  Whether to resume previous training, looks for models per iteration (def.=$RESUME)";
      echo " -T THREADS   Threads for parallel processing, max. 99 (def.=$THREADS)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
  local FEATLST="$1";
  local TEXTTAB="$2";
  shift 2;
  while [ $# -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      OUTDIR="$2";
    #elif [ "$1" = "-P" ]; then
    #  PROTO="$2";
    elif [ "$1" = "-fb" ]; then
      FB="$2";
    elif [ "$1" = "-k" ]; then
      KEEPITERS="$2";
    elif [ "$1" = "-m" ]; then
      KEEPMISC="$2";
    elif [ "$1" = "-r" ]; then
      RESUME="$2";
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
  elif [ ! -e "$TEXTTAB" ]; then
    echo "$FN: error: table text file not found: $TEXTTAB" 1>&2;
    return 1;
  #elif [ "$PROTO" != "" ] && [ ! -e "$PROTO" ]; then
  #  echo "$FN: error: initialization prototype not found: $PROTO" 1>&2;
  #  return 1;
  fi

  local TMPDIR="$OUTDIR";
  local TEXTPART="$TEXTTAB";

  ### Divide data by number of threads or create a single feats table ###
  local FEATSPERTHR=$(( ( $(wc -l < "$FEATLST") + THREADS - 1 ) / THREADS ));
  if [ "$THREADS" -gt 1 ]; then
    [ $FEATSPERTHR -le 1 ] && FEATSPERTHR="2";
    rm -f "$OUTDIR/hmms_train_feats_part_"*;
    awk '{printf("%s %s\n",rand(),$0)}' "$FEATLST" \
      | sort \
      | sed 's|^[^ ]* ||' \
      | split --numeric-suffixes -l $FEATSPERTHR - "$OUTDIR/hmms_train_feats_part_";
    THREADS=$(ls "$OUTDIR/hmms_train_feats_part_"* | wc -l);
    THREADS=$(echo $(seq -f %02.0f 0 $((THREADS-1))) | tr ' ' ',');
    TEXTPART="$OUTDIR/hmms_train_text_part_JOBID";
  else
    cat "$FEATLST" > "$OUTDIR/hmms_train_feats_part_1";
  fi

  local t;
  for t in ${THREADS//,/ }; do
    [ "$THREADS" != "1" ] &&
      sed 's|.*/||; s|\.fea$||' "$OUTDIR/hmms_train_feats_part_$t" \
        | awk '
            { if( FILENAME != "-" )
                PART[$1] = $0;
              else if( $1 in PART )
                print PART[$1];
            }' "$TEXTTAB" - \
        > "$OUTDIR/hmms_train_text_part_$t";
    htrsh_feats_htk_to_kaldi "$OUTDIR/hmms_train_feats_part_$t" < "$OUTDIR/hmms_train_feats_part_$t";
  done
  cat "$OUTDIR"/hmms_train_feats_part_*.scp > "$OUTDIR/hmms_train_feats.scp";

  ### Create lexicon ###
  awk '
    { for( n=2; n<=NF; n++ )
        print $n;
    }' "$TEXTTAB" \
    | sort -u \
    | awk '
        { printf( "%-25s 1  ", $1 );
          for( m=1; m<=length($1); m++ )
            printf( " %s", substr($1,m,1) );
          printf( "\n" );
        }' \
    > "$OUTDIR/Lexicon.txt";

  local ndisambig=$(utils/add_lex_disambig.pl --pron-probs "$OUTDIR/Lexicon.txt" "$OUTDIR/Lexicon_disambig.txt");

  # Create list of character IDs
  awk '{ for(n=3;n<=NF;n++) print $n; }' "$OUTDIR/Lexicon.txt" \
    | sort -u \
    | gawk '
        BEGIN {
          printf("<eps> 0\n");
          printf("0x20 %d\n",++NCHARS);
        }
        { if( $1 == "<eps>" || $1 == "0x20" || match($1,/^#[0-9]+$/) )
            printf("warning: lexicon contains special character: %s\n",$1) > "/dev/stderr";
          else
            printf("%s %d\n",$1,++NCHARS);
        }
        END {
          for( n=0; n<='$ndisambig'; n++ )
            printf("#%d %d\n",n,++NCHARS);
        }' \
    > "$OUTDIR/Lexicon_chars.txt";

  local nchars=$(( $(wc -l < "$OUTDIR/Lexicon_chars.txt") - ndisambig - 2 ));

  # Create list of word IDs
  awk '
    BEGIN { printf("<eps> 0\n"); }
    { if( $1 == "<eps>" || $1 == "<s>" || $1 == "</s>" )
        printf("warning: lexicon contains special word: %s\n",$1) > "/dev/stderr";
      else
        printf("%s %d\n",$1,++NWORDS);
    }
    END {
      printf("#0 %d\n",++NWORDS);
      printf("<s> %d\n",++NWORDS);
      printf("</s> %d\n",++NWORDS);
    }' "$OUTDIR/Lexicon.txt" \
    > "$OUTDIR/Lexicon_words.txt";

  # Create lexicon FST
  utils/make_lexicon_fst.pl --pron-probs "$OUTDIR/Lexicon.txt" 0.5 0x20 \
    | fstcompile \
        --isymbols="$OUTDIR/Lexicon_chars.txt" \
        --osymbols="$OUTDIR/Lexicon_words.txt" \
        --keep_isymbols=false --keep_osymbols=false \
    | fstarcsort --sort_type=olabel \
    > "$OUTDIR/Lexicon.fst";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems creating Lexicon FST" 1>&2 &&
    return 1;

  #fstprint --isymbols="$OUTDIR/Lexicon_chars.txt" --osymbols="$OUTDIR/Lexicon_words.txt" "$OUTDIR/Lexicon.fst" | less

  ### Initialization ###
  #if [ "$PROTO" != "" ]; then
  #else
  #  RESUME="no";

    { echo "<Topology>";
      echo "<TopologyEntry>";
      echo "<ForPhones>";
      echo $(seq 1 $nchars);
      echo "</ForPhones>";
      local s;
      for s in $(seq 0 $(($htrsh_hmm_states-1))); do
        echo "<State> $s <PdfClass> $s <Transition> $s 0.6 <Transition> $((s+1)) 0.4 </State>";
      done
      echo "<State> $htrsh_hmm_states </State>";
      echo "</TopologyEntry>";
      echo "</Topology>";
    } > "$OUTDIR/Topology.txt";

    # Initialize HMMs
    local DIMS=$(HList -z -h $(head -n 1 "$FEATLST") \
                   | sed -n '/Num Comps:/{s|.*Num Comps: *||;s| .*||;p;}');
    gmm-init-mono \
      --train-feats=scp:"$OUTDIR/hmms_train_feats.scp" \
      "$OUTDIR/Topology.txt" \
      "$DIMS" \
      "| gzip > $OUTDIR/hmms_g00_i00.mdl.gz" \
      "$OUTDIR/hmms_tree";
    [ "$?" != 0 ] &&
      echo "$FN: error: problems initializing HMMs" 1>&2 &&
      return 1;

    #gmm-copy --binary=false "zcat $OUTDIR/hmms_g00_i00.mdl.gz |" - | less
    #tree-info tmp/hmms_tree

    ### Compile train graphs ###
    htrsh_run_parallel $THREADS compile-train-graphs \
      "$OUTDIR/hmms_tree" \
      "zcat $OUTDIR/hmms_g00_i00.mdl.gz |" \
      "$OUTDIR/Lexicon.fst" \
      "ark:utils/sym2int.pl -f 2- $OUTDIR/Lexicon_words.txt < $TEXTPART |" \
      "ark:| gzip > $OUTDIR/hmms_train_graphs_JOBID.gz";
    #  "ark:utils/sym2int.pl -f 2- $OUTDIR/Lexicon_words.txt < $OUTDIR/hmms_train_text_part_JOBID |" \
    [ "$?" != 0 ] &&
      echo "$FN: error: problems compiling train graphs" 1>&2 &&
      return 1;

    #fstcopy "ark:zcat $OUTDIR/hmms_train_graphs_00.gz |" 'scp,p:echo JA.Jv3-001.t1.t1_l02 -|' | fstprint --osymbols=$OUTDIR/Lexicon_words.txt - | less

  #fi

  local TS=$(($(date +%s%N)/1000000));

  ### Training loop ###
  local g i;
  local rangei="0 $htrsh_hmm_iter";
  local prevg="00";
  local previ="00";
  local igauss=$(octave -q --eval "printf('%.2d',log($htrsh_hmm_nummix)/log(2))");
  local ngauss=$(gmm-info "zcat $OUTDIR/hmms_g${prevg}_i${previ}.mdl.gz |" 2>/dev/null \
                   | sed -n '/gaussians/{s|.* ||;p;}');

  for g in $(seq -f %02.0f 0 ${igauss#0}); do
    for i in $(seq -f %02.0f $rangei); do
      if [ "$i" != "00" ] &&
         [ "$RESUME" != "no" ] &&
         [ -e "$OUTDIR/hmms_g${g}_i${i}.mdl.gz" ]; then
        RESUME="hmms_g${g}_i${i}.mdl.gz";
        continue;
      fi
      [ "$RESUME" != "no" ] && [ "$RESUME" != "yes" ] &&
        echo "$FN: info: resuming from $RESUME" 1>&2;
      RESUME="no";

      if [ "$i" = "00" ]; then
        ### Initial alignment ###
        echo "$FN: info: initial alignment" 1>&2;
        htrsh_run_parallel $THREADS align-equal-compiled \
          "ark:zcat $OUTDIR/hmms_train_graphs_JOBID.gz |" \
          "scp:$OUTDIR/hmms_train_feats_part_JOBID.scp" \
          "ark,t:| gzip > $OUTDIR/hmms_g${g}_i${i}_ali.JOBID.gz";
        [ "$?" != 0 ] &&
          echo "$FN: error: failed in align-equal-compiled" 1>&2 &&
         return 1;
        rangei="1 $htrsh_hmm_iter";
      else
        local TS2=$(($(date +%s%N)/1000000));
        ### Subsequent alignments / forward-backward ###
        echo "$FN: info: $htrsh_kaldi_mixfact^${g#0} Gaussians re-estimation iteration $i" 1>&2;
        local CMD="gmm-align-compiled $htrsh_kaldi_gmmalign_opts";
        [ "$FB" = "yes" ] && CMD="gmm-fb-compiled $htrsh_kaldi_gmmfb_opts";
        # @note In the original Kaldi recipe, silence models are boosted using
        # gmm-boost-silence tool --boost=0.75 1 model_1.mdl model_1_ali.md
        htrsh_run_parallel $THREADS $CMD \
          "zcat $OUTDIR/hmms_g${prevg}_i${previ}.mdl.gz |" \
          "ark:zcat $OUTDIR/hmms_train_graphs_JOBID.gz |" \
          "scp:$OUTDIR/hmms_train_feats_part_JOBID.scp" \
          "ark,t:| gzip > $OUTDIR/hmms_g${g}_i${i}_ali.JOBID.gz";
        [ "$?" != 0 ] &&
          echo "$FN: error: failed in gmm-align-compiled" 1>&2 &&
           return 1;
        echo "$FN: time align/fb: $(($(($(date +%s%N)/1000000))-TS2)) ms" 1>&2;
      fi

      local TS2=$(($(date +%s%N)/1000000));
      ### Accumulate alignment statistics ###
      local CMD="gmm-acc-stats-ali";
      [ "$FB" = "yes" ] && [ "$i" != "00" ] && CMD="gmm-acc-stats";
      htrsh_run_parallel $THREADS $CMD \
        "zcat $OUTDIR/hmms_g${prevg}_i${previ}.mdl.gz |" \
        "scp:$OUTDIR/hmms_train_feats_part_JOBID.scp" \
        "ark,t:zcat $OUTDIR/hmms_g${g}_i${i}_ali.JOBID.gz |" \
        "$OUTDIR/hmms_g${g}_i${i}_acc.JOBID";
      [ "$?" != 0 ] &&
        echo "$FN: error: failed in gmm-acc-stats-ali" 1>&2 &&
        return 1;

      ### Maximum Likelihood re-estimation ###
      local gmmest_opts=(
        "${htrsh_kaldi_gmmest_opts[@]}"
        --write-occs="$OUTDIR/hmms_g${g}_i${i}.occ" );
      [ "$i" = "01" ] && [ "$g" != "00" ] &&
        gmmest_opts=( "${gmmest_opts[@]}" "--mix-up=$ngauss" );

      gmm-est "${gmmest_opts[@]}" \
        "zcat $OUTDIR/hmms_g${prevg}_i${previ}.mdl.gz |" \
        "gmm-sum-accs - $OUTDIR/hmms_g${g}_i${i}_acc.* |" \
        "| gzip > $OUTDIR/hmms_g${g}_i${i}.mdl.gz";
      [ "$?" != 0 ] &&
        echo "$FN: error: failed in gmm-est" 1>&2 &&
        return 1;
      echo "$FN: time accum+reest: $(($(($(date +%s%N)/1000000))-TS2)) ms" 1>&2;

      rm "$OUTDIR"/hmms_g${g}_i${i}_{ali,acc}.*;

      local TE=$(($(date +%s%N)/1000000)); echo "$FN: time g=$htrsh_kaldi_mixfact^${g#0} i=$i: $((TE-TS)) ms" 1>&2; TS="$TE";

      [ "$KEEPITERS" = "no" ] && [ "$i" != "00" ] &&
        rm -f "$OUTDIR"/hmms_g${prevg}_i${previ}.{mdl.gz,occ};

      previ="$i";
      prevg="$g";
    done

    ngauss=$(echo $htrsh_kaldi_mixfact $ngauss \
               | awk '{v=$1*$2; print (v==int(v))?v:int(v)+1}');
  done

  [ "$RESUME" != "no" ] && [ "$RESUME" != "yes" ] &&
    echo "$FN: warning: model already trained $RESUME" 1>&2;

  echo "$OUTDIR/hmms_g${g}_i${i}.mdl.gz";

  if [ "$KEEPMISC" != "yes" ]; then
    rm "$OUTDIR/hmms_train_feats_part_"* "$OUTDIR/hmms_train_feats.scp";
    rm "$OUTDIR/hmms_train_graphs_"*;
  fi
  rm -f "$OUTDIR/hmms_train_text_part_"*;
  #rm "$OUTDIR/hmms_tree" "$OUTDIR/Topology.txt";

  return 0;
}

#if false; then

##
## Function that does a line by line forced alignment given only a page with baselines or contours and optionally a model
##
htrsh_pageimg_forcealign_kaldi () {
  local FN="htrsh_pageimg_forcealign_kaldi";
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
  if [ "$htrsh_align_prefer_baselines" = "yes" ] ||
     [ $(xmlstarlet sel -t -v \
           "count($htrsh_xpath_regions/_:TextLine/$htrsh_xpath_coords)" \
           "$XML") = 0 ]; then
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
    SFACT=$(echo "100*$SFACT/$IMRES" | bc -l);
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
    # { echo '#!MLF!#';
    #  htrsh_pagexml_textequiv "$TMPDIR/${XMLBASE}_feats.xml" -f mlf-chars -r $AREG -F "$FILTER";
    #} > "$TMPDIR/${B}_page.mlf";
    #[ "$?" != 0 ] && return 1;
    htrsh_pagexml_textequiv "$TMPDIR/${XMLBASE}_feats.xml" -f tab > "$TMPDIR/${B}_page.txt";
    MODEL=$(
      #htrsh_hmm_train "$TMPDIR/${B}_feats.lst" "$TMPDIR/${B}_page.mlf" -d "$TMPDIR" \
      #####htrsh_hmm_train_kaldi "$TMPDIR/${B}_feats.lst" "$TMPDIR/${B}_page.txt" -d "$TMPDIR" \
      htrsh_hmm_train_kaldi "$TMPDIR/${B}_feats.lst" "$TMPDIR/${B}_page.txt" -d "$TMPDIR" -m yes \
        2> "$TMPDIR/${XMLBASE}_hmmtrain.log" -fb "$FB"
      );
    [ "$?" != 0 ] &&
      echo "$FN: error: problems training model, more info might be in file $TMPDIR/${XMLBASE}_hmmtrain.log" 1>&2 &&
      return 1;
  #else
  # @todo Align even if given model does not include some characters in the page. Add missing HMMs with a simple proto or average. How to handle possible different names of special characters, e.g. space: @, 0x20.
  fi
  [ ! -e "$MODEL" ] &&
    echo "$FN: error: model file not found: $MODEL" 1>&2 &&
    return 1;

  ### Do forced alignment using model ###
  echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): doing forced alignment ...";
  #if [ "$AREG" = "yes" ]; then
  #  cp "$TMPDIR/${XMLBASE}_feats.xml" "$TMPDIR/${XMLBASE}_align.xml";
  #  local id;
  #  for id in $(xmlstarlet sel -t -m "$htrsh_xpath_regions" -v @id -n "$XML"); do
  #    echo "$FN ($(date -u '+%Y-%m-%d %H:%M:%S')): aligning region $id";
  #    htrsh_pageimg_forcealign_region "$TMPDIR/${XMLBASE}_align.xml" "$id" \
  #      "$TMPDIR" "$MODEL" "$TMPDIR/${XMLBASE}_align-.xml" -d "$TMPDIR" \
  #      >> "$TMPDIR/${XMLBASE}_forcealign.log";
  #    [ "$?" != 0 ] &&
  #      echo "$FN: error: more info might be in file $TMPDIR/${XMLBASE}_forcealign.log" 1>&2 &&
  #      return 1;
  #    mv "$TMPDIR/${XMLBASE}_align-.xml" "$TMPDIR/${XMLBASE}_align.xml";
  #  done
  #  cp -p "$TMPDIR/${XMLBASE}_align.xml" "$XMLOUT";
  #else
  #  htrsh_pageimg_forcealign_lines \
  #    "$TMPDIR/${XMLBASE}_feats.xml" "$TMPDIR/${B}_feats.lst" "$MODEL" \
  #    "$XMLOUT" -d "$TMPDIR" \
  #    > "$TMPDIR/${XMLBASE}_forcealign.log";
    htrsh_pageimg_forcealign_lines_kaldi \
      "$TMPDIR/${XMLBASE}_feats.xml" "$TMPDIR/hmms_train_feats.scp" \
      "$TMPDIR/hmms_train_graphs_1.gz" "$MODEL" "$XMLOUT" -d "$TMPDIR" \
      > "$TMPDIR/${XMLBASE}_forcealign.log";

    [ "$?" != 0 ] &&
      echo "$FN: error: more info might be in file $TMPDIR/${XMLBASE}_forcealign.log" 1>&2 &&
      return 1;
  #fi 2>&1;

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

##
## Function that does a forced alignment at a line level for a given XML Page, feature list and model
##
htrsh_pageimg_forcealign_lines_kaldi () {
  local FN="htrsh_pageimg_forcealign_lines_kaldi";
  local TMPDIR=".";
  if [ $# -lt 5 ]; then
    { echo "$FN: Error: Not enough input arguments";
      echo "Description: Does a forced alignment at a line level for a given XML Page, feature list and model";
      echo "Usage: $FN XMLIN FEATSCP TXTGRAPHS MODEL XMLOUT [ Options ]";
      echo "Options:";
      echo " -d TMPDIR    Directory for temporary files (def.=$TMPDIR)";
    } 1>&2;
    return 1;
  fi

  ### Parse input arguments ###
# @todo maybe give text table not text graphs, and create function for creating the graphs
  local XML="$1";
  local FEATSCP="$2";
  local TXTGRAPHS="$3";
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

  if ! [ -e "$XML" ]; then
    echo "$FN: error: Page XML file not found: $XML" 1>&2;
    return 1;
  elif ! [ -e "$FEATSCP" ]; then
    echo "$FN: error: features scp file not found: $FEATSCP" 1>&2;
    return 1;
  elif ! [ -e "$TXTGRAPHS" ]; then
    echo "$FN: error: text graphs file not found: $TXTGRAPHS" 1>&2;
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
  # { echo '#!MLF!#'; htrsh_pagexml_textequiv "$XML" -f mlf-chars; } > "$TMPDIR/$B.mlf";
  #[ "$?" != 0 ] &&
  #  echo "$FN: error: problems creating MLF file: $XML" 1>&2 &&
  #  return 1;

  ### Create auxiliary files: HMM list and dictionary ###
  #local HMMLST=$(zcat "$MODEL" | sed -n '/^~h "/{ s|^~h "||; s|"$||; p; }');
  #local DIC=$(echo "$HMMLST" | awk '{printf("\"%s\" [%s] 1.0 %s\n",$1,$1,$1)}');

  ### Do forced alignment with HVite ###
  #HVite $htrsh_HTK_HVite_opts -C <( echo "$htrsh_HTK_config" ) -H "$MODEL" -S "$FEATLST" -m -I "$TMPDIR/$B.mlf" -i "$TMPDIR/${B}_aligned.mlf" <( echo "$DIC" ) <( echo "$HMMLST" );

  ### Create text table from XML and train graphs ###
  htrsh_pagexml_textequiv "$XML" -f tab > "$TMPDIR/$B.txt";
  # @todo create text graphs

  ### Do forced alignment with gmm-align-compiled ###
# @todo try gmm-align-compiled --careful=true 
  gmm-align-compiled $htrsh_kaldi_gmmalign_opts \
      "zcat $MODEL |" \
      "ark:zcat $TXTGRAPHS |" \
      "scp:$FEATSCP" \
      ark,t:- 2>/dev/null \
    | ali-to-phones --write-lengths --print-args=false \
        "zcat $MODEL |" \
        ark:- ark,t:- 2>/dev/null \
    | awk '
      { if( FILENAME != "-" )
          map[$2] = $1;
        else {
          for(n=2;n<=NF;n+=3)
            $n = map[$n];
          for(n=4;n<=NF;n+=3)
            $n = "";
          print;
        }
      }' "$TMPDIR/Lexicon_chars.txt" - \
  | sed 's|   *| |g' \
  | awk -v TEXTTAB="$TMPDIR/$B.txt" '
      BEGIN { print("#!MLF!#"); }
      { getline text < TEXTTAB;
        NW = split(text,wtext," ");
        if( $1 != wtext[1] ) {
          printf("error: unexpected line order: %s vs. %s\n",$1,wtext[1]) > "/dev/stderr";
          exit 1;
        }
        printf("\"*/%s.rec\"\n",$1);
        f = 0;
        c = 2;
        for( w=2; w<=NW; w++ ) {
          if( $c == "0x20" ) {
            printf( "%d %d @\n", 100000*f, 100000*(f+$(c+1)-1) );
            f += $(c+1);
            c += 2;
          }
          else
            printf( "%d %d @\n", 100000*f, 100000*f );
          NC = split(wtext[w],chars,"");
          for( nc=1; nc<=NC; nc++ ) {
            if( chars[nc] != $c ) {
              printf("error: unmatched word: %s (%s, word=%d, char=%d)\n",wtext[w],$1,w-1,nc) > "/dev/stderr";
              exit 1;
            }
            cc = $c;
            gsub( "{",    "{lbrace}", cc );
            gsub( "}",    "{rbrace}", cc );
            gsub( "@",    "{at}",     cc );
            gsub( "\"",   "{dquote}", cc );
            gsub( "\x27", "{quote}",  cc );
            gsub( "&",    "{amp}",    cc );
            gsub( "<",    "{lt}",     cc );
            gsub( ">",    "{gt}",     cc );
            printf( "%d %d %s\n", 100000*f, 100000*(f+$(c+1)-1), cc );
            #printf( "%d %d %s\n", f, f+$(c+1)-1, $c );
            f += $(c+1);
            c += 2;
          }
        }
        if( $c == "0x20" ) {
          printf( "%d %d @\n", 100000*f, 100000*(f+$(c+1)-1) );
          f += $(c+1);
          c += 2;
        }
        else
          printf( "%d %d @\n", 100000*f, 100000*f );
        printf(".\n");
        if( c <= NF ) {
          printf("error: characters remaining and no words to output (%s)\n",$1) > "/dev/stderr";
          exit 1;
        }
      }' \
    > "$TMPDIR/${B}_aligned.mlf";
  [ "$?" != 0 ] &&
    echo "$FN: error: problems aligning: $XML" 1>&2 &&
    return 1;

  ### Insert alignment information in XML ###
  htrsh_pagexml_insertalign_lines "$XML" "$TMPDIR/${B}_aligned.mlf" \
    > "$XMLOUT";
  [ "$?" != 0 ] &&
    return 1;

  htrsh_fix_rec_names "$XMLOUT";

  #[ "$htrsh_keeptmp" -lt 1 ] &&
  #  rm -f "$TMPDIR/$B.mlf" "$TMPDIR/${B}_aligned.mlf";

  return 0;
}


#fi
