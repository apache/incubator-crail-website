# which column 
if [ $# -ne 2 ]; then 
	echo "tell me file name and col number"
	exit 1
fi
k=$2
file=$1 

# sort it 
sort --key $k -n $file > $file-sort 

# now we generate CDF 
totalLines=$(cat $file-sort | wc -l)
echo "total line numbers: $totalLines" 
rm ./xx
for i in `seq 1 100`;
do 
   lx=$(( $i * $totalLines ))
   lxx=$(( $lx / 100 )) # you get the line number here 
   sed -n "${lxx}p" $file-sort >> ./xx
done    
cat ./xx | awk '{print $1,"\t",NR}' > cdf-$file
