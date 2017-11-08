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
  * 8 node x86_64 cluster
* Node configuration
  * CPU: 2 x Intel(R) Xeon(R) CPU E5-2690 0 @ 2.90GHz
  * DRAM: 96GB DDR4
  * Network: 1x100Gbit/s Mellanox ConnectX-5
* Software
  * Ubuntu 16.04.3 LTS (Xenial Xerus) with Linux kernel version 4.10.0-33-generic
  * Crail 1.0, version 2995
  * <a href="https://github.com/Mellanox/SparkRDMA">SparkRDMA</a>, commit d95ce3e370a8e3b5146f4e0ab5e67a19c6f405a5 (latest master on 8th of November 2017)

### Spark Shuffle Plugins
<div style="text-align: justify">
<p>
Recently there has been interest by the community to include a RDMA accelerated
shuffle engine into the Spark codebase (<a href="https://issues.apache.org/jira/browse/SPARK-22229">Proposal</a>).
The design proposes to improve shuffle performance by performing
data transfers over RDMA. For this, the code manages its own off-heap memory
which needs to be registered with the NIC for RDMA use. Furthermore, the authors
claim that using the plugin architecture for shuffle engines in Spark
introduces limitations and overheads that reduce performance.
A prototype implementation of the design is available as open-source
shuffle plugin here:
<a href="https://github.com/Mellanox/SparkRDMA">https://github.com/Mellanox/SparkRDMA</a>.
Note that the current prototype implementation supports two ways to store shuffle
data between the stages: (1) shuffle data is stored like in vanilla Spark
on disk. (2) data is stored in memory allocated and registered for RDMA transfer.
<br/><br/>
In constrast, the Crail approach is quite different. Crail was designed as a
storage bus for intermediate data. We believe the Crail's modular architecture
to leverage high-performance storage and networking devices for e.g.
shuffle data has many advantages over a tightly integrated design like
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
method and writes shuffle data to disk between stages (2) the ChunkedPartitionAgg
(beta) stores shuffle data in memory. We evaluate both writer methods for
terasort and SQL equijoin.
</p>
</div>
<br>
<div style="text-align:center"><img src ="/img/blog/rdma-shuffle/terasort.svg" width="750"/></div>
<br>
<div style="text-align: justify">
<p>
</p>
</div>
<br>
<div style="text-align:center"><img src ="/img/blog/rdma-shuffle/sql.svg" width="750"/></div>
<br>

