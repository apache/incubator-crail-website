---
layout: post
title: "Spark Shuffle: SparkRDMA vs Crail (DRAFT)"
author: Jonas Pfefferle, Patrick Stuedi, Animesh Trivedi, Bernard Metzler, Adrian Schuepbach
category: blog
comments: true
---

<div style="text-align: justify">
<p>
This blog is comparing the performance of different RDMA-based shuffle plugins for Spark.
</p>
</div>

### Hardware Configuration

The specific cluster configuration used for the experiments in this blog:

* Cluster
  * 8 compute + 1 management node x86_64 cluster
* Node configuration
  * CPU: 2 x Intel(R) Xeon(R) CPU E5-2690 0 @ 2.90GHz
  * DRAM: 96GB DDR3
  * Network: 1x100Gbit/s Mellanox ConnectX-5
* Software
  * Ubuntu 16.04.3 LTS (Xenial Xerus) with Linux kernel version 4.10.0-33-generic
  * Crail 1.0, commit a45c8382050f471e9342e1c6cf25f9f2001af6b5
  * <a href="https://github.com/Mellanox/SparkRDMA">SparkRDMA</a>, commit d95ce3e370a8e3b5146f4e0ab5e67a19c6f405a5 (latest master on 8th of November 2017)

### Spark Shuffle Plugins
<div style="text-align: justify">
<p>
Recently there has been interest by the community to include a RDMA accelerated
shuffle engine into the Spark codebase (<a href="https://issues.apache.org/jira/browse/SPARK-22229">Proposal</a>).
The design proposes to improve shuffle performance by performing
data transfers over RDMA. For this, the code manages its own off-heap memory
which needs to be registered with the NIC for RDMA use.
A prototype implementation of the design is available as open-source
shuffle plugin here:
<a href="https://github.com/Mellanox/SparkRDMA">https://github.com/Mellanox/SparkRDMA</a>.
Note that the current prototype implementation supports two ways to store shuffle
data between the stages: (1) shuffle data is stored like in vanilla Spark
in files, (2) data is stored in memory allocated and registered for RDMA transfer.
<br/><br/>
In constrast, the Crail approach is different as it was designed as a
storage bus for intermediate data. We believe the Crail's modular architecture
to leverage high-performance storage and networking devices for e.g.
shuffle data has many advantages over a "last-mile" design like
the one described above: no overhead of allocation and registration of data
stored between stages, disaggregation support, seamless support for
different storage types (e.g. RAM, NVMe, ...), tiering, Inter-Job data storage,
...
</p>
</div>

### Performance comparison
<div style="text-align: justify">
<p>
In the previous blogs we have already shown that Crail can achieve great
speedup compared to vanilla Spark. Let us see how SparkRDMA holds up in comparison.
As described above, SparkRDMA allows to switch how the shuffle data is handled
between the stages by configuring a shuffle writer
(spark.shuffle.rdma.shuffleWriterMethod): (1) Is called the Wrapper shuffle writer
method and wrappes the Spark shuffle writer, i.e. writes shuffle data to
files between stages, (2) the ChunkedPartitionAgg (beta) stores shuffle data
in memory. We evaluate both writer methods for terasort and SQL equijoin.
</p>
</div>
<br>
<div style="text-align:center"><img src ="/img/blog/rdma-shuffle/terasort.svg" width="750"/></div>
<br>
<div style="text-align: justify">
<p>
First we run <a href="https://github.com/zrlio/crail-spark-terasort">terasort</a>
on our 8+1 machine cluster (see above). We sort 200GB, i.e. each nodes gets 25GB 
of data (equal distribution). To get the best possible configuration for
all setups we brute-force the configuration space for each of them.
All configuration use 8 executors with 12 cores each. Note that
in a typical Spark run more CPU cores than assigned are engaged because of
garbabge collection, etc. In our test runs assigning 12 cores lead to the
best performance.<br/><br/>

The plot above shows runtimes of the various configuration we run with terasort.
SparkRDMA with the Wrapper shuffle writer performance slightly better (3-4%) than
vanilla Spark whereas the Chunked shuffle writer shows a 30% overhead. A quick
inspection found that this overhead stems from memory allocation and registration
for the shuffle data to be kept in memory between the stages. Crail's shuffle
plugin shows performance improvement of around 235%.
</p>
</div>
<br>
<div style="text-align:center"><img src ="/img/blog/rdma-shuffle/sql.svg" width="750"/></div>
<br>

<div style="text-align: justify">
<p>
For our second workload we choose the
<a href="https://github.com/zrlio/sql-benchmarks">SQL equijoin</a> with a
<a href="https://github.com/zrlio/spark-nullio-fileformat">special fileformat</a>
that allows data to be generated on the fly, i.e. this benchmark focuses on
shuffle performance. The shuffle data size is around 148GB. Here the
Wrapper shuffle writer is slightly slower than vanilla Spark but instead the
Chunked shuffle writer is roughly the same amount faster. Crail again shows a
great performance increase over vanilla Spark.<br/><br/>
These benchmarks validate our previous statements that we believe a
"last-mile" integration cannot deliver the same performance as a holistic
approach, i.e. one has to look at the whole picture in how to integrate
RDMA into Spark applications. Replacing only the data transfer alone does not
lead to the anticipated performance increase. We learned this the hard
way when we intially started working on Crail.
</p>
</div>

