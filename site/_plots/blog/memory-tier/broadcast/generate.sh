if [ $# -ne 1 ]; then 
	echo "which file"
	exit 1 
fi 
 
totalLines=$(cat $1 | wc -l)
echo "total line numbers: $totalLines" 
rm ./xx
for i in `seq 1 100`;
do 
   lx=$(( $i * $totalLines ))
   lxx=$(( $lx / 100 ))
   sed -n "${lxx}p" $1 >> ./xx
done    

cat ./xx | awk '{print $1,"\t",NR}' > cdf-$1
