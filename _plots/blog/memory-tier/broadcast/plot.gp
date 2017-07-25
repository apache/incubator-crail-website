set terminal pdf color font "Times-Roman, 20"  
set output "cdf-broadcast-128-read.pdf"
set yrange [0:100]
set ylabel "CDF"

set xlabel "read 128b broadcast latency"
set xrange [1:100000]

set xtics ( "1us" 1,\
"10us" 10,\
"100us" 100,\
"1ms" 1000,\
"10ms" 10000,\
"100ms" 100000)

set logscale x

set grid

set key bottom right maxrows 3 samplen 1 

plot 'cdf-crail' using 1:2 title "crail" with lines lc rgb "green" lw 4,\
'cdf-vanilla' using 1:2 title "vanilla" with lines lc rgb "red" lw 4,\
'cdf-network-read' using 1:2 notitle with lines lc rgb "grey" lw 4
