


htrsh_exp_dataset="";  # Name of dataset
htrsh_exp_cvparts="4"; # Number of cross-validation partitions

htrsh_exp_feat_name=""; # Name for feature extraction configuration

htrsh_run_threads="1";   # Number of parallel threads
htrsh_run_tmpdir="/tmp"; # Directory for temporal files

htrsh_feat_imgres="";  # If set, resize pages to given resolution in dpi
htrsh_feat_pcabase=""; # If set, use provided PCA base
htrsh_feat_pcaopts="-e 1:4 -r 24"; # Options for PCA computation

htrsh_tokenizer="cat"; # Pipe command for tokenization
htrsh_canonizer="cat"; # Pipe command for canonization

htrsh_hvite_gsf="10"; # Grammar Scale Factor used to compute word graphs
htrsh_hvite_wip="0";  # Word Insertion Penalty used to compute word graphs
htrsh_hvite_beam="-n 15 1"; # Beam search parameters

htrsh_exp_hvite_gsf="0 3 5 10 20 30 50"; # List of Grammar Scale Factors for HLRescore
htrsh_exp_hvite_wip="50 30 20 10 5 0 -5 -10 -20 -30 -50 -70 -90 -110"; # List of Word Insertion Penalties for HLRescore

htrsh_exp_partial=""; # Run experiment until step: feats, lang, hmm

##
## Perform/continue a cross-validation HTR experiment
##
# @todo Train mlf (done) and decoding dictionary should depend on parameters to allow experimentation with other HMM structures
htrsh_exp_htr_cv () {(
  FN="htrsh_exp_htr_cv";

  LANG="en_US.UTF-8";
  LC_ALL="en_US.UTF-8";
  TMPDIR="$htrsh_run_tmpdir";
  THREADS="$htrsh_run_threads";
  MAGICK_TEMPORARY_PATH="$TMPDIR";
  MAGICK_THREAD_LIMIT="1";
  OMP_NUM_THREADS="1";
  EXPDIR=$(pwd);
  PARTS=$(seq 0 $((htrsh_exp_cvparts-1)));

  STATES="$htrsh_hmm_states";

  DATASET="$htrsh_exp_dataset";
  FEATNAME="$htrsh_exp_feat_name";
  [ "$FEATNAME" = "" ] &&
    FEATNAME="unnamed~"$(ls "$EXPDIR/feats/$DATASET"/unnamed~* 2>/dev/null | wc -l);


  ### General checks ###
  htrsh_check_dependencies 2>&1;
  if [ "$?" != 0 ]; then
    echo "$FN: error: unmet dependencies" 1>&2;
    return 1;
  elif [ "$DATASET" = "" ]; then
    echo "$FN: error: expected dataset name in variable htrsh_exp_dataset" 1>&2;
    return 1;
  elif [ ! -d "data/$DATASET" ] ||
       [ $(ls data/$DATASET/*.xml 2>/dev/null | wc -l) = 0 ]; then
    echo "$FN: error: expected xml files in dataset directory: data/$DATASET" 1>&2;
    return 1;
  fi

  mkdir -p "$TMPDIR";
  cd "$TMPDIR";

  echo "$FN: HTR experiment for dataset $DATASET";


  ### Feature extraction ###
  FDIR="$EXPDIR/feats/$DATASET/$FEATNAME";
  if [ ! -d "$FDIR/orig" ]; then
    echo "$FN: computing $FEATNAME features";
    TS=$(($(date +%s%N)/1000000));

    mkdir -p $FDIR/orig;
    mkdir -p $FDIR/tmp;

    ### Change image to resolution FEATRES dpi and then extract features ###
    extract_feats () {
      local f="$1";
      local ff=$(echo $f | sed 's|.*/||; s|\.xml$||;');

      if [ "$htrsh_feat_imgres" != "" ]; then
        htrsh_pageimg_resize "$f" "$FDIR/orig" -o $(echo "$htrsh_feat_imgres/2.54" | bc -l);
        htrsh_pageimg_clean "$FDIR/orig/$ff.xml" "$FDIR/tmp";
        mv "$FDIR/tmp/$ff".* "$FDIR/orig";
      else
        htrsh_pageimg_clean "$f" "$FDIR/orig";
      fi

      htrsh_xpath_lines="_:TextLine[$htrsh_xpath_textequiv]" \
        htrsh_pageimg_extract_linefeats "$FDIR/orig/$ff.xml" "$FDIR/orig/${ff}_feats.xml" \
          -d "$FDIR/orig";
      mv "$FDIR/orig/${ff}_feats.xml" "$FDIR/orig/$ff.xml";
    }

    ls "$EXPDIR/data/$DATASET/"*.xml \
      | run_parallel -n 1 -T $THREADS -l - \
          extract_feats '{*}' &> $FDIR/feats.log;

    ls "$FDIR/orig/"*.{jpg,tif} 2>/dev/null | xargs rm -f;
    rmdir "$FDIR/tmp";
    gzip -n "$FDIR/orig/"*.xml;

    TE=$(($(date +%s%N)/1000000)); echo "$FN: computing $FEATNAME features: time $((TE-TS)) ms";
  fi


  ### Create lists for CV partitions ###
  if [ ! -d "$EXPDIR/lists/$DATASET" ]; then
    echo "$FN: creating cross-validation partitions";

    mkdir -p "$EXPDIR/lists/$DATASET";
    ls "$EXPDIR/data/$DATASET/"*.xml \
      | sed 's|.*/||; s|\.xml$||;' \
      > "$EXPDIR/lists/$DATASET/pages.lst";
    P=$( htrsh_randsplit $htrsh_exp_cvparts "$EXPDIR/lists/$DATASET/pages.lst" "$EXPDIR/lists/$DATASET/pages_part%d.lst" );
    if [ "$P" != "$htrsh_exp_cvparts" ]; then
      echo "$FN: error: unable to generate $htrsh_exp_cvparts partitions";
      rm -r "$EXPDIR/lists/$DATASET";
      return 1;
    fi
    sed 's|^|^|; s|$|\\.|;' -i "$EXPDIR/lists/$DATASET/pages_part"*.lst;

    for p in $PARTS; do
      ls "$EXPDIR/feats/$DATASET/$FEATNAME/orig/"*.fea \
        | sed 's|.*/||' \
        | grep -f "$EXPDIR/lists/$DATASET/pages_part$p.lst" \
        > "$EXPDIR/lists/$DATASET/feats_part$p.lst";
    done
    cat "$EXPDIR/lists/$DATASET/feats_part"*.lst > "$EXPDIR/lists/$DATASET/feats.lst";

    for p in $PARTS; do
      cat "$EXPDIR/lists/$DATASET/feats_part$p.lst" "$EXPDIR/lists/$DATASET/feats_part"*.lst \
        | sort \
        | uniq -u \
        > "$EXPDIR/lists/$DATASET/feats_train_part$p.lst";
    done
  fi

  ### Project features with PCA for each CV partition ###
  if [ ! -d "$EXPDIR/feats/$DATASET/$FEATNAME/pca_part0" ]; then
    for p in $PARTS; do
      FDIR="$EXPDIR/feats/$DATASET/$FEATNAME/pca_part$p";
      [ -e "$FDIR" ] &&
        continue;
      if [ "$htrsh_feat_pcabase" = "single" ]; then
        ln -s pca_part0 "$FDIR";
        continue;
      fi

      echo "$FN: PCA for partition $p";
      TS=$(($(date +%s%N)/1000000));

      { mkdir -p "$FDIR";
        sed "s|^|$EXPDIR/feats/$DATASET/$FEATNAME/orig/|" "$EXPDIR/lists/$DATASET/feats_train_part$p.lst" \
          | xargs ls -f \
          > "$FDIR/feats_train_part$p.lst";
        sed "s|^|$EXPDIR/feats/$DATASET/$FEATNAME/orig/|" "$EXPDIR/lists/$DATASET/feats_part$p.lst" \
          | xargs ls -f \
          > "$FDIR/feats_part$p.lst";

        ### Compute PCA ###
        PCABASE="$EXPDIR/$htrsh_feat_pcabase";
        if [ "$htrsh_feat_pcabase" = "" ] || [ "$htrsh_feat_pcabase" = "single" ]; then
          PCABASE="$FDIR/pcab.mat.gz";
          htrsh_feats_pca "$FDIR/feats_train_part$p.lst" "$PCABASE" $htrsh_feat_pcaopts -T $THREADS;
          [ "$?" != 0 ] &&
            echo "$FN: error: problems computing PCA for partition $p" &&
            return 1;
        fi

        ### Project features ###
        cat "$FDIR/feats_train_part$p.lst" "$FDIR/feats_part$p.lst" \
          | run_parallel -T $THREADS -n balance -l - \
              htrsh_feats_project '{@}' "$PCABASE" "$FDIR";
        [ "$?" != 0 ] &&
          echo "$FN: error: problems projecting partition $p" &&
          return 1;

        rm "$FDIR"/feats{,_train}_part$p.lst;
      } > "$EXPDIR/feats/$DATASET/$FEATNAME/pca.log";

      TE=$(($(date +%s%N)/1000000)); echo "$FN: PCA for partition $p: time $((TE-TS)) ms";
    done

    [ $(ls "$EXPDIR/feats/$DATASET/$FEATNAME/orig/"*.fea 2>/dev/null | wc -l) != 0 ] &&
      rm "$EXPDIR/feats/$DATASET/$FEATNAME/orig/"*.fea;
  fi

  [ "$htrsh_exp_partial" = "feats" ] && return 0;

  ### Train language models ###
  if [ ! -d "$EXPDIR/models/$DATASET/lang" ]; then
    echo "$FN: training language models";
    TS=$(($(date +%s%N)/1000000));

    mkdir -p "$EXPDIR/models/$DATASET/lang";
    for f in "$EXPDIR/data/$DATASET/"*.xml; do
      htrsh_pagexml_textequiv "$f" -f tab;
    done > "$EXPDIR/models/$DATASET/lang/pages.txt";

    for p in $PARTS; do
      MDIR="$EXPDIR/models/$DATASET/lang/part$p";
      mkdir -p "$MDIR";
      sed 's|\.fea$||' "$EXPDIR/lists/$DATASET/feats_train_part$p.lst" \
        | awk '
            { if( FILENAME == "-" )
                ids[$1] = "";
              else if( $1 in ids )
                print;
            }' - "$EXPDIR/models/$DATASET/lang/pages.txt" \
        | sed 's|^[^ ]* ||' \
        | htrsh_langmodel_train - -d "$MDIR" \
            -T "$htrsh_tokenizer" \
            -C "$htrsh_canonizer";
      gzip -n "$MDIR"/text_* "$MDIR"/langmodel_*;
    done

    ### Compute OOV and ROOV ###
    echo "# OOV ROOV OOV_canonic ROOV_canonic" > "$EXPDIR/models/$DATASET/oov.txt";
    for p in $PARTS; do
      MDIR="$EXPDIR/models/$DATASET/lang/part$p";
      awk '{print $2}' "$MDIR/dictionary.txt" \
        | sed 's|^\[||; s|]$||; /^$/d;' \
        | sort -u \
        > voc.txt;
      awk '{print $2}' "$MDIR/dictionary.txt" \
        | sed 's|^\[||; s|]$||; /^$/d;' \
        | "$htrsh_canonizer" \
        | sort -u \
        > voc_canonic.txt;

      sed 's|\.fea$||' "$EXPDIR/lists/$DATASET/feats_part$p.lst" \
        | awk '
            { if( FILENAME == "-" )
                ids[$1] = "";
              else if( $1 in ids )
                print;
            }' - "$EXPDIR/models/$DATASET/lang/pages.txt" \
        | sed 's|^[^ ]* ||' \
        | "$htrsh_tokenizer" \
        | tee gnd.txt \
        | "$htrsh_canonizer" \
        > gnd_canonic.txt;

      echo \
        $( oov.py -n voc.txt -t gnd.txt | awk '{printf(" %s %s",$7,$16)}' ) \
        $( oov.py -n voc_canonic.txt -t gnd_canonic.txt | awk '{printf(" %s %s",$7,$16)}' );

      rm voc.txt voc_canonic.txt;
      rm gnd.txt gnd_canonic.txt;
    done >> "$EXPDIR/models/$DATASET/oov.txt";

    #awk '{ if($1!="#") { PARTS++; for(n=1;n<=NF;n++) s[n]+=$n; } } END { for(n=1;n<=NF;n++) printf("%.1f\n",s[n]/PARTS) }' "$EXPDIR/models/$DATASET/oov.txt";

    ### Compute PPLs ###
    tokenizer_and_canonizer () { "$htrsh_tokenizer" | "$htrsh_canonizer"; }
    for f in "$EXPDIR/data/$DATASET/"*.xml; do
      htrsh_pagexml_textequiv "$f" -f tab -F tokenizer_and_canonizer;
    done > "$EXPDIR/models/$DATASET/lang/pages.txt";

    for p in $PARTS; do
      sed 's|\.fea$||' "$EXPDIR/lists/$DATASET/feats_part$p.lst" \
        | awk '
            { if(FILENAME=="-")
                ids[$1]="";
              else if($1 in ids)
                print;
            }' - "$EXPDIR/models/$DATASET/lang/pages.txt" \
        | sed 's|^[^ ]* ||' \
        | ngram -lm <( zcat "$EXPDIR/models/$DATASET/lang/part$p/langmodel_2-gram.arpa.gz" ) -ppl - \
        | sed 'N; s|^file -: ||; s|\n| |;';
    done > "$EXPDIR/models/$DATASET/ppl.txt";

    rm "$EXPDIR/models/$DATASET/lang/pages.txt";

    TE=$(($(date +%s%N)/1000000)); echo "$FN: training language models: time $((TE-TS)) ms";
  fi


  ### Create MLFs for training and test ###
  if [ ! -d "$EXPDIR/groundtruth/$DATASET" ]; then
    echo "$FN: creating ground truth files";

    mkdir -p "$EXPDIR/groundtruth/$DATASET";
    { echo '#!MLF!#';
      for f in "$EXPDIR/data/$DATASET/"*.xml; do
        htrsh_pagexml_textequiv "$f" -f mlf-words -F "$htrsh_tokenizer";
      done
    } > "$EXPDIR/groundtruth/$DATASET/pages_test.mlf";
  fi

  [ "$htrsh_exp_partial" = "lang" ] && return 0;

  ### Train HMM models ###
  for htrsh_hmm_states in $STATES; do
    MDIR="$EXPDIR/models/$DATASET/${htrsh_hmm_type}_hmm_s$htrsh_hmm_states";

    if [ ! -e "$MDIR/pages_train.mlf" ]; then
      mkdir -p "$MDIR";
      { echo '#!MLF!#';
        for f in "$EXPDIR/data/$DATASET/"*.xml; do
          htrsh_pagexml_textequiv "$f" -f mlf-chars -F "$htrsh_tokenizer";
        done
      } > "$MDIR/pages_train.mlf";
    fi

    for p in $PARTS; do
      MDIR="$EXPDIR/models/$DATASET/${htrsh_hmm_type}_hmm_s$htrsh_hmm_states/$FEATNAME/part$p";
      [ -d "$MDIR" ] &&
        continue;
      echo "$FN: training HMMs for partition $p";
      TS=$(($(date +%s%N)/1000000));

      mkdir -p "$MDIR";
      { sed "s|^|$EXPDIR/feats/$DATASET/$FEATNAME/pca_part$p/|;" "$EXPDIR/lists/$DATASET/feats_train_part$p.lst" \
          | xargs ls -f \
          > "$MDIR/feats_train_part$p.lst";
        htrsh_hmm_train "$MDIR/feats_train_part$p.lst" "$MDIR/../../pages_train.mlf" \
          -d "$MDIR" -T $THREADS;
      } &> "$MDIR/train.log";
      gzip -n "$MDIR/train.log";

      for i in $(seq -f %02.0f 0 $((htrsh_hmm_iter-1))); do
        rm "$MDIR/"Macros_hmm_g???_i$i.gz;
      done
      rm "$MDIR/feats_train_part$p.lst";

      TE=$(($(date +%s%N)/1000000)); echo "$FN: training HMMs for partition $p: time $((TE-TS)) ms";
    done
  done

  [ "$htrsh_exp_partial" = "hmm" ] && return 0;

  ### Recognize pages for the different parameters ###
  for states in $STATES; do
    for gauss in $htrsh_hmm_nummix; do # @todo not being varied in training
      gauss="g0${gauss}_i0${htrsh_hmm_iter}"; # @todo improve this
      param="s${states}_${gauss}_gsf${htrsh_hvite_gsf}_wip${htrsh_hvite_wip}";
      DDIR="$EXPDIR/decode/$DATASET/$FEATNAME/lat_$param";

      mkdir -p "$DDIR";

      ### Generate word-graphs ###
      if [ ! -e "$DDIR/$param.mlf.gz" ]; then
        for p in $PARTS; do
          [ -e "$DDIR/part$p.mlf.gz" ] &&
            continue;
          echo "$FN: computing word-graphs for parameters $param and partition $p";
          TS=$(($(date +%s%N)/1000000));

          { LM="$EXPDIR/models/$DATASET/lang/part$p/langmodel_2-gram.lat.gz";
            DIC="$EXPDIR/models/$DATASET/lang/part$p/dictionary.txt";
            HMM="$EXPDIR/models/$DATASET/${htrsh_hmm_type}_hmm_s$states/$FEATNAME/part$p/Macros_hmm_$gauss.gz";
            HMMLST=$(zcat $HMM | sed -n '/^~h/{s|^~h "||;s|"$||;p;}');

            sed "s|^|$EXPDIR/feats/$DATASET/$FEATNAME/pca_part$p/|;" "$EXPDIR/lists/$DATASET/feats_part$p.lst" \
              | xargs ls -f \
              > "$DDIR/feats_part$p.lst";

            htrsh_hvite_parallel $THREADS HVite -C <( echo "$htrsh_HTK_config" ) \
              $htrsh_hvite_beam -z lat.gz -q ABtvalr \
              -s $htrsh_hvite_gsf -p $htrsh_hvite_wip -H "$HMM" \
              -S "$DDIR/feats_part$p.lst" -i "$DDIR/part$p.mlf" -l "$DDIR" \
              -w "$LM" "$DIC" <( echo "$HMMLST" );

            gzip -n "$DDIR/part$p.mlf";
            #rm "$DDIR/feats_part$p.lst";

          } &>> "$DDIR/hvite.log";

          TE=$(($(date +%s%N)/1000000)); echo "$FN: computing word-graphs for parameters $param and partition $p: time $((TE-TS)) ms";
        done
      fi

      ### Join recognition for all partitions ###
      if [ ! -e "$DDIR/$param.mlf.gz" ] &&
         [ $(ls "$DDIR/"part*.mlf 2>/dev/null | wc -l) = 0 ] &&
         [ $(ls "$DDIR/"part*.mlf.gz | wc -l) = "$htrsh_exp_cvparts" ]; then
        #echo "$FN: creating $DDIR/$param.mlf.gz";
        zcat "$DDIR"/part*.mlf.gz \
          | htrsh_fix_rec_mlf_quotes - \
          | sed '1p; /^#!MLF!#/d; s|^".*/feats/.*/|"*/|; s|^".*/decode/.*/|"*/|;' \
          | gzip \
          > "$DDIR/$param.mlf.gz";
      fi

      ### Use word-graphs to decode for different parameters ###
      wg="s${states}_${gauss}_gsf${htrsh_hvite_gsf}_wip${htrsh_hvite_wip}";
      DDIR="$EXPDIR/decode/$DATASET/$FEATNAME/rescore_$wg";

      mkdir -p "$DDIR";

      rescore_gsf_wip_part () {
        local gsf=$(echo $1 | awk '{print $1}');
        local wip=$(echo $1 | awk '{print $2}');
        local p=$(echo $1 | awk '{print $3}');
        local param=$(echo $wg | sed "s|_gsf[0-9.-]*_wip[0-9.-]*||")"_gsf${gsf}_wip${wip}";

        ### Rescore for given GSF and WIP ###
        if [ ! -e "$DDIR/${param}_part$p.mlf.gz" ]; then
          local DIC="$EXPDIR/models/$DATASET/lang/part$p/dictionary.txt";

          [ ! -e "$DDIR/part$p.lst" ] &&
            sed "s|^|$EXPDIR/decode/$DATASET/$FEATNAME/lat_$wg/|; s|\.fea\$|.lat.gz|;" \
                "$EXPDIR/lists/$DATASET/feats_part$p.lst" \
              | xargs ls -f \
              | sed 's|\.gz$||' \
              > "$DDIR/part$p.lst";

          HLRescore -C <( echo "$htrsh_HTK_config" ) -f \
            -s $(printf '%.9f' $gsf) -p $(printf '%.9f' $wip) \
            -X lat.gz -i "$DDIR/${param}_part$p.mlf" -S "$DDIR/part$p.lst" "$DIC";

          gzip -n "$DDIR/${param}_part$p.mlf";
        fi

        ### Join recognition for all partitions ###
        if [ ! -e "$DDIR/$param.mlf.gz" ] &&
           [ $(ls "$DDIR/"${param}_part*.mlf 2>/dev/null | wc -l) = 0 ] &&
           [ $(ls "$DDIR/"${param}_part*.mlf.gz | wc -l) = $htrsh_exp_cvparts ]; then
          zcat "$DDIR/"${param}_part*.mlf.gz \
            | htrsh_fix_rec_mlf_quotes - \
            | sed '1p; /^#!MLF!#/d; s|^".*/decode/.*/|"*/|;' \
            | gawk '
                { if( FILENAME == "-" ) {
                    if( match($0,/^"\*\//) )
                      rec[ gensub( /^"\*\/(.+)\.rec"$/, "\\1.fea", "", $0 ) ] = "";
                    print;
                  }
                  else if( ! ( $0 in rec ) )
                    printf("\"*/%s.rec\"\n.\n", gensub(/\.fea$/,"","",$0) );
                }' - "$EXPDIR/lists/$DATASET/feats.lst" \
            | gzip \
            > "$DDIR/$param.mlf.gz";
        fi
      }

      ### Parallel rescoring ###
      if [ $(( $(echo $htrsh_exp_hvite_gsf | wc -w)*$(echo $htrsh_exp_hvite_wip | wc -w) )) != $(ls "$DDIR/"*.mlf.gz 2>/dev/null | grep -v _part | wc -l) ]; then
        echo "$FN: computing rescores for parameters $param";
        TS=$(($(date +%s%N)/1000000));
        awk '
          BEGIN {
            nGSF = split( "'"$htrsh_exp_hvite_gsf"'", GSF );
            nWIP = split( "'"$htrsh_exp_hvite_wip"'", WIP );
            nPARTS = split( "'"$(echo $PARTS)"'", PARTS );
            for ( g=1; g<=nGSF; g++ )
              for ( w=1; w<=nWIP; w++ )
                for ( p=1; p<=nPARTS; p++ )
                  printf( "%s %s %s\n", GSF[g], WIP[w], PARTS[p] );
          }' | run_parallel -T $THREADS -n 1 -l - rescore_gsf_wip_part '{*}';
        TE=$(($(date +%s%N)/1000000)); echo "$FN: rescores for parameters $param: time $((TE-TS)) ms";
      fi


      ### Compute evaluation measures: WER and CER ###
      wg="s${states}_${gauss}_gsf${htrsh_hvite_gsf}_wip${htrsh_hvite_wip}";
      DDIR="$EXPDIR/decode/$DATASET/$FEATNAME/rescore_$wg";

      [ -e "$DDIR.txt" ] &&
        continue;
      [ $(( $(echo $htrsh_exp_hvite_gsf | wc -w)*$(echo $htrsh_exp_hvite_wip | wc -w) )) != $(ls "$DDIR/"*.mlf.gz 2>/dev/null | grep -v _part | wc -l) ] &&
        continue;

      echo "$FN: computing evaluation measures for parameters $param";
      TS=$(($(date +%s%N)/1000000));
      for f in $(ls "$DDIR"/*.mlf.gz | grep -v _part); do
        htrsh_mlf_to_tasas \
            "$EXPDIR/groundtruth/$DATASET/pages_test.mlf" \
            <( zcat "$f" ) \
          > "$DDIR/evaluate_${wg}_wer.txt";
        htrsh_mlf_to_tasas \
            "$EXPDIR/groundtruth/$DATASET/pages_test.mlf" \
            <( zcat "$f" ) \
            -c yes \
          > "$DDIR/evaluate_${wg}_cer.txt";
        #htrsh_mlf_to_tasas \
        #    <( "$htrsh_canonizer" < "$EXPDIR/groundtruth/$DATASET/pages_test.mlf" ) \
        #    <( zcat "$f" | "$htrsh_canonizer" ) \
        #  > "$DDIR/evaluate_${wg}_canonic_wer.txt";

        echo \
          $( tasas "$DDIR/evaluate_${wg}_wer.txt" -ie -s " " -f "|" ) \
          $( tasas "$DDIR/evaluate_${wg}_cer.txt" -ie -s " " -f "|" ) \
          - \
          $( echo "$f" | sed 's|.*/decode/||;s|\.mlf\.gz||;' );
          #$( tasas "$DDIR"/evaluate_${wg}_canonic_wer.txt -ie -s " " -f "|" ) \

        rm -f "$DDIR"/evaluate_${wg}_{w,c}er.txt "$DDIR/"evaluate_${wg}_canonic_{w,c}er.txt;
      done > "$DDIR.txt";
      TE=$(($(date +%s%N)/1000000)); echo "$FN: evaluation measures parameters $param: time $((TE-TS)) ms";

      #[ $(( $(echo $htrsh_exp_hvite_gsf | wc -w)*$(echo $htrsh_exp_hvite_wip | wc -w) )) = $(cat $DDIR.txt | wc -l) ] &&
      #  rm "$EXPDIR/decode/$DATASET/$FEATNAME/lat_$param/"*.lat.gz;
    done
  done

  echo "$FN: finished experiment for dataset $DATASET";
)}




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
