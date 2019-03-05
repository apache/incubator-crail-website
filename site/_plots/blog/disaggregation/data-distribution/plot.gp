#set terminal pdf monochrome font "Times-Roman, 18"  
set term svg size 640,300 font "Times-Roman, 12"
set output "cdf-plot.svg"
# this is always 0->100
set yrange [0:100]
set ylabel "CDF" offset 1

set xlabel "data size" offset 0,0.5 font ",18"
set xrange [1:1073741824]

#set style line 1 lc rgb "#000000" pt 6 dt 1 lw 2 ps 0
#set style line 2 lc rgb "#000000" pt 6 dt 2 lw 2 ps 0
#set style line 3 lc rgb "#000000" pt 6 dt 4 lw 2 ps 0
#set style line 4 lc rgb "#000000"  pt 6 dt 5 lw 2 ps 0

set style increment user

set xtics 4 format ""
set xtics add ( "1" 1,\
"1kB" 1024,\
"1MB" 1048576,\
"1GB" 1073741824)

set logscale x 2

set ytics 10
set grid

set key top left maxrows 3 samplen 2 font ",18"

plot './tpcds/cdf-all.data' using 1:2 title "TPC-DS" with lines lw 4 lt 1 lc 7, \
'./graph/cdf-all.data' using 1:2 title "PR-Twitter" with lines lw 4 lt 8 lc 6


#'./ml/cdf-all.data' using 1:2 title "ML-Cocoa" with lines lw 4 lt 2 lc 6,\
