---
layout: post
title: "Spark Shuffle: SparkRDMA vs Crail"
author: Jonas Pfefferle, Patrick Stuedi, Animesh Trivedi, Bernard Metzler, Adrian Schuepbach
category: blog
mode: guest
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
  * <a href="https://github.com/zrlio/crail">Crail 1.0</a>, commit a45c8382050f471e9342e1c6cf25f9f2001af6b5
  * <a href="">Crail Shuffle plugin</a>, commit 2273b5dd53405cab3389f5c1fc2ee4cd30f02ae6 
  * <a href="https://github.com/Mellanox/SparkRDMA">SparkRDMA</a>, commit d95ce3e370a8e3b5146f4e0ab5e67a19c6f405a5 (latest master on 8th of November 2017)

### Overview
<div style="text-align: justify">
<p>
Lately there has been an increasing interest in the community to include RDMA networking into data processing frameworks like Spark and Hadoop. One natural spot to integrate RDMA is in the shuffle operation that involves all-to-all network communication pattern. Naturally, due to its performance requirements the shuffle operation is of interest to us as well, and we have developed a Spark plugin for shuffle. In our previous blog posts, we have already shown that the Crail Shuffler achieves great workload-level speedups compared to vanilla Spark. In this blog post, we take a look at another recently proposed design called <a href="https://github.com/Mellanox/SparkRDMA">SparkRDMA</a> (<a href="https://issues.apache.org/jira/browse/SPARK-22229">SPARK-22229 JIRA</a>). SparkRDMA proposes to improve the shuffle performance of Spark by performing data transfers over RDMA. For this, the code manages its own off-heap memory which needs to be registered with the NIC for RDMA use. It supports two ways to store shuffle data between the stages: (1) shuffle data is stored in regular files (just like vanilla Spark) but the data transfer is implemented via RDMA, (2) data is stored in memory (allocated and registered for RDMA transfer) and the data transfer is implemented via RDMA. We call it the "last-mile" approach where just the networking operations are replaced by the RDMA operations.
</p>
<p>
In contrast, the Crail shuffler plugin takes a more holistic approach and leverages the high performance of Crail distributed data store to deliver gains. It uses Crail store to efficiently manage I/O resources, storage and networking devices, memory registrations, client sessions, data distribution, etc. Consequently, the shuffle operation becomes as simple as writing and reading files. And recall that Crail store is designed as a fast data bus for the intermediate data. The shuffle operation is just one of many operations that can be accelerated using Crail store. Beyond these operations, the modular architecture of Crail store enables us to seamlessly leverage different storage types (DRAM, NVMe, and more), perform tiering, support disaggregation, share inter-job data, jointly optimize I/O resources for various workloads, etc. These capabilities and performance gains give us confidence in the design choices we made for the Crail project.
</p>
</div>

### Performance comparison
<div style="text-align: justify">
<p>Lets start by quantitatively assessing performance gains from the Crail shuffle plugin and SparkRDMA. As described above, SparkRDMA can be operated in two different modes. Users decide which mode to use by selecting a particular type of shuffle writer (spark.shuffle.rdma.shuffleWriterMethod). The Wrapper shuffle writer writes shuffle data to files between the stages, the Chunked shuffle writer stores shuffle data in memory. We evaluate both writer methods for terasort and SQL equijoin.
</p>
</div>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/rdma-shuffle/terasort.svg" width="550"/></div>
<br>
<div style="text-align: justify">
<p>
First we run <a href="https://github.com/zrlio/crail-spark-terasort">terasort</a> on our 8+1 machine cluster (see above). We sort 200GB, thus, each node gets 25GB of data (equal distribution). We further did a basic search of the parameter space for each of the systems to find the best possible configuration. In all the experiments we use 8 executors with 12 cores each. Note that in a typical Spark run more CPU cores than assigned are engaged because of garbabge collection, etc. In our test runs assigning 12 cores lead to the best performance.
</p>
<p>
The plot above shows runtimes of the various configuration we run with terasort. SparkRDMA with the Wrapper shuffle writer performance slightly better (3-4%) than vanilla Spark whereas the Chunked shuffle writer shows a 30% overhead. On a quick inspection we found that this overhead stems from memory allocation and registration for the shuffle data that is kept in memory between the stages. Compared to vanilla Spark, Crail's shuffle plugin shows performance improvement of around 235%.
</p>
</div>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/rdma-shuffle/sql.svg" width="550"/></div>
<br>

<div style="text-align: justify">
<p>
For our second workload we choose the <a href="https://github.com/zrlio/sql-benchmarks">SQL equijoin</a> with a <a href="https://github.com/zrlio/spark-nullio-fileformat">special fileformat</a> that allows data to be generated on the fly. By generating data on the fly we eliminate any costs for reading data from storage and focus entirely on the shuffle performance. The shuffle data size is around 148GB. Here the Wrapper shuffle writer is slightly slower than vanilla Spark but instead the Chunked shuffle writer is roughly the same amount faster. The Crail shuffle plugin again delivers a great performance increase over vanilla Spark.
</p>
</div>

<div style="text-align: justify">
<p>Please let us know if your have recommendations about how these experiments can be improved.</p>
</div>

### Summary

<div style="text-align: justify">
<p>
These benchmarks validate our belief that a "last-mile" integration cannot deliver the same performance gains as a holistic approach, i.e. one has to look at the whole picture in how to integrate RDMA into Spark applications (and for that matter any framework or application). Only replacing the data transfer alone does not lead to the anticipated performance increase. We learned this the hard way when we intially started working on Crail.
</p>

</div>

