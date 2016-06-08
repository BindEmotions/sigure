#!/bin/bash

# デフォルト値セット
unset make
screen="disable"
thread=4

# 色表示部
red=31
green=32
yellow=33
blue=34

function outcr {
        color=$1
        shift
        echo -e "\033[${color}m$@\033[m" $3
}

# 環境チェック
## このプログラムの動作にはscreenコマンドが必要です
(type screen) >& /dev/null
if [ $? -eq 1 ]; then
        outcr $red "screenがインストールされていません。" 1>&2
        outcr $red "動作に必要ですのでインストールしてください。" 1>&2
        outcr $red "Ubuntuであれば apt-get install screen で入ります。"
        check="true"
fi

# 異常時の終了処理及びヘルプ表示
usage_exit(){
        echo -e "\n使用法: $0 [-d dir] [-r "device"] [-c] [-s] [-t] [-j thread] [-m]" 1>&2
        echo -e "-r: brunchビルドを実行するデバイスネームを指定" 1>&2
        echo -e "-d: コマンドを実行するディレクトリを現在位置からの相対パスか絶対パスで指定" 1>&2
        echo -e "-c: make cleanを行う(オプション)" 1>&2
        echo -e "-s: repo syncを行うか(オプション)" 1>&2
        echo -e "-t: ツイートを行うか(オプション)" 1>&2
	echo -e "-j: repo sync及び-mオプション時のmakeのスレッド数指定(オプション)" 1>&2
	echo -e "-m: brunchではなくmakeで実行する(オプション)" 1>&2
        exit 1
}

# 引数処理
while getopts d:r:j:cstmx var
do
    case $var in
        d) shdir=$OPTARG
           (ls $shdir) >& /dev/null
           if [ $? -eq 2 ]; then
              outcr $red "指定されたディレクトリが存在しません。文字列が間違っていないか確認してください。" 1>&2
              check="true"
           fi
           ;;
        r) device=$OPTARG ;;
        c) optmc="-c" ;;
        s) optrs="-s" ;;
        t) tweet="-t" ;;
	j) thread=$OPTARG ;;
	m) make="enable" ;;
        x) screen="enable" ;;
    esac
done

if [ "$shdir" = "" ]; then
        outcr $red "ディレクトリが指定されていません。指定してください。" 1>&2
        check="true"
fi

if [ "$device" = "" ]; then
        outcr $red "デバイスが指定されていません。指定してください。" 1>&2
        check="true"
fi

cd $shdir >& /dev/null && source build/envsetup.sh >& /dev/null
breakfast $device >& /dev/null
if [ $? -ne 0 ]; then
        outcr $red "デバイスツリーが存在しないか不正です。入力が間違っていないか確認してください。" 1>&2
        check="true"
fi
cd ..

if [ "$check" = "true" ]; then
	usage_exit
fi

# screenで起動しているか確認
if [ "$screen" != "enable" ]; then
        screen $0 "$@" -x
        exit 0
fi

# ビルド処理
## ビルドフォルダへの移動
cd $shdir

## 事前設定
source=$shdir
logfolder="log"
zipfolder="zip"

## 設定情報を取得
(ls ./config.sh) >& /dev/null
if [ $? -eq 0 ]; then
        . ./config.sh
fi
(ls ../config.sh) >& /dev/null
if [ $? -eq 0 ]; then
        . ../config.sh
fi

# 事前フォルダ作成
mkdir -p ../$logfolder
mkdir -p ../$zipfolder

## build/envsetup.shの読み込み
source build/envsetup.sh >& /dev/null
breakfast $device >& /dev/null


## repo syncを行うか確認
if [ "$optrs" = "-s" ]; then
	## デフォルト値セット
	startsynctime=$(date '+%m/%d %H:%M:%S')
	startsync="$source の repo sync を開始します。\n$startsynctime"
	
	# 設定情報を取得
	(ls ../config.sh) >& /dev/null
	if [ $? -eq 0 ]; then
	        . ../config.sh
	fi
	
        outcr $blue "repo syncを開始します。"
	if [ "$tweet" = "-t" ]; then
		echo -e $startsync | python ../tweet.py
	fi

        repo sync -j$thread --force-sync

	if [ "$tweet" = "-t" ]; then
	        if [ $(echo ${PIPESTATUS[0]}) -eq 0 ]; then
			res=0
        	else
			res=1
        	fi
		endsynctime=$(date '+%m/%d %H:%M:%S')
		endsync="$source の repo sync が正常終了しました。\n$endsynctime"
		stopsync="$source の repo sync が異常終了しました。\n$endsynctime"
		(ls ../config.sh) >& /dev/null
		if [ $? -eq 0 ]; then
			. ../config.sh
		fi
		if [ $res -eq 0 ]; then
			echo -e $endsync | python ../tweet.py
		else
			echo -e $stopsync | python ../tweet.py
		fi
	fi
fi

## make cleanを行うか確認
if [ "$optmc" = "-c" ]; then
        outcr $blue "make cleanを開始します。"
        make clean
fi

## 設定情報取得前設定
logfiletime=$(date '+%Y-%m-%d_%H-%M-%S')
logfilename="${logfiletime}_${shdir}_${device}"
model=$(cat device/*/$device/cm.mk 2>&1 | grep 'PRODUCT_MODEL' | cut -c 18-)
if [ "$model" = "" ]; then
        model=$(cat device/*/$device/full_$device.mk 2>&1 | grep 'PRODUCT_MODEL' | cut -c 18-)
fi
if [ "$model" = "" ]; then
        model=$device
fi
starttime=$(date '+%m/%d %H:%M:%S')
zipdate=$(date -u '+%Y%m%d')
getvar=$(get_build_var CM_VERSION)
zipname=$getvar
if [ "$zipname" = "" ]; then
        zipname="*"
fi
starttwit="$device 向け $source のビルドを開始します。\n$starttime"

## ソースフォルダ内設定情報を取得
(ls ./config.sh) >& /dev/null
if [ $? -eq 0 ]; then
        . ./config.sh
fi

## 設定情報を取得
(ls ../config.sh) >& /dev/null
if [ $? -eq 0 ]; then
        . ../config.sh
fi

## ビルド開始ツイート処理
if [ "$tweet" = "-t" ]; then
        echo -e $starttwit | python ../tweet.py
fi

## ビルド実行
LANG=C
if [ "$make" = "enable" ]; then
	outcr $blue "ビルドをmakeで開始します。"
	make -j$thread 2>&1 | tee "../$logfolder/$logfilename.log"
else
	outcr $blue "ビルドをbrunchで開始します。"
	brunch $device 2>&1 | tee "../$logfolder/$logfilename.log"
fi


### ビルドが成功したか確認します。
if [ $(echo ${PIPESTATUS[0]}) -eq 0 ]; then
        res=0
else
        res=1
fi

### ファイル移動
if [ $res -eq 0 ]; then
        mv --backup=t out/target/product/${device}/${zipname}.zip ../${zipfolder}
fi
cd ..

### 設定情報取得前設定
unset endstr
endstr=$(tail -2 "$logfolder/$logfilename.log" | head -1 | grep "#" | cut -d "#" -f 5 | cut -c 2- | sed 's/ (hh:mm:ss)//g' | sed 's/ (mm:ss)//g' | sed 's/ seconds)/s/g' | sed 's/(//g' | sed 's/)//g')
endtime=$(date '+%m/%d %H:%M:%S')
stoptwit="$model 向け $source のビルドが失敗しました。\n$endstr\n$endtime"
endtwit="$model 向け $source のビルドが成功しました!\n$endstr\n$endtime"
endziptwit="$model のビルドに成功しました!\n$endstr\n$endtime"

### 設定情報を取得
(ls ./config.sh) >& /dev/null
if [ $? -eq 0 ]; then
        . ./config.sh
fi

### ビルド終了ツイート処理
if [ "$tweet" = "-t" ]; then
        if [ $res -eq 0 ]; then
                if [ "$zipname" != "*" ]; then
                        echo -e $endziptwit | python tweet.py
                else
                        echo -e $endtwit | python tweet.py
                fi
        else
                echo -e $stoptwit | python tweet.py
        fi
fi

### ビルドのコマンドと同じ終了ステータスを渡す
exit $res
