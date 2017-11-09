---
layout: post
title: "Spark Shuffle: SparkRDMA vs Crail (DRAFT)"
author: Jonas Pfefferle, Patrick Stuedi, Animesh Trivedi, Bernard Metzler, Adrian Schuepbach
category: blog
comments: true
---

<div style="text-align: justify">
<p>
This blog is comparing the shuffle performance of Crail with SparkRDMA, an alternative RDMA-based shuffle plugin for Spark.
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
Recently there has been increasing interest by the community to include a RDMA accelerated shuffle engine into the Spark codebase (<a href="https://issues.apache.org/jira/browse/SPARK-22229">Proposal</a>). The design proposes to improve the shuffle performance of Spark by performing data transfers over RDMA. For this, the code manages its own off-heap memory which needs to be registered with the NIC for RDMA use. A prototype implementation of the design is available as part of the SparkRDMA open-source codebase (<a href="https://github.com/Mellanox/SparkRDMA">https://github.com/Mellanox/SparkRDMA</a>). The SparkRDMA shuffle plugin supports two ways to store shuffle data between the stages: (1) shuffle data is stored in regular files (just like vanilla Spark) but the data transfer is implemented via RDMA, (2) data is stored in memory (allocated and registered for RDMA transfer) and the data transfer is implemented via RDMA.
</p>
<p>
In constrast, the Crail approach is different. Crail was designed as a storage bus for intermediate data. We believe that Crail's modular architecture to leverage high-performance storage and networking devices for e.g. shuffle data has many advantages over a "last-mile" design like SparkRDMA: no overhead of allocation and registration of data stored between stages, disaggregation support, seamless support for different storage types (e.g. RAM, NVMe, ...), tiering, inter-job data storage, ...
</p>
</div>

### Performance comparison
<div style="text-align: justify">
<p>
In our previous blog posts we have shown that Crail can achieve a great speedup compared to vanilla Spark. Let us see how SparkRDMA holds up in comparison. As described above, SparkRDMA can be operated in two different modes. Users decide which mode to use by selecting a particular type of shuffle writer (spark.shuffle.rdma.shuffleWriterMethod). The Wrapper shuffle writer writes shuffle data to files between the stages, the Chunked shuffle writer stores shuffle data in memory. We evaluate both writer methods for terasort and SQL equijoin.
</p>
</div>
<div style="text-align:center"><img src ="/img/blog/rdma-shuffle/terasort.svg" width="550"/></div>
<br>
<div style="text-align: justify">
<p>
First we run <a href="https://github.com/zrlio/crail-spark-terasort">terasort</a> on our 8+1 machine cluster (see above). We sort 200GB, thus, each node gets 25GB of data (equal distribution). We further did a basic search of the parameter space for each of the systems to find the best possible configuration. In all the experiments we use 8 executors with 12 cores each. Note that in a typical Spark run more CPU cores than assigned are engaged because of garbabge collection, etc. In our test runs assigning 12 cores lead to the best performance.
</p>
<p>
The plot above shows runtimes of the various configuration we run with terasort. SparkRDMA with the Wrapper shuffle writer performance slightly better (3-4%) than vanilla Spark whereas the Chunked shuffle writer shows a 30% overhead. On a quick inspection we found that this overhead stems from memory allocation and registration for the shuffle data that is kept in memory between the stages. Compared to vanilla Spark, Crail's shuffle plugin shows performance improvement of around 235%.
</p>
</div>
<div style="text-align:center"><img src ="/img/blog/rdma-shuffle/sql.svg" width="550"/></div>
<br>

<div style="text-align: justify">
<p>
For our second workload we choose the <a href="https://github.com/zrlio/sql-benchmarks">SQL equijoin</a> with a <a href="https://github.com/zrlio/spark-nullio-fileformat">special fileformat</a> that allows data to be generated on the fly. By generating data on the fly we eliminate any costs for reading data from storage and focus entirely on the shuffle performance. The shuffle data size is around 148GB. Here the Wrapper shuffle writer is slightly slower than vanilla Spark but instead the Chunked shuffle writer is roughly the same amount faster. Crail again shows a great performance increase over vanilla Spark.
</p>
</div>

### Summary

<div style="text-align: justify">
<p>
These benchmarks validate our previous statements that we believe a "last-mile" integration cannot deliver the same performance as a holistic approach, i.e. one has to look at the whole picture in how to integrate RDMA into Spark applications. Only replacing the data transfer alone does not lead to the anticipated performance increase. We learned this the hard way when we intially started working on Crail.
</p>
</div>

