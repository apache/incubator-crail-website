---
layout: post
title: "Shuffle Disaggregation using RDMA accessible remote DRAM and NVMe Flash"
author: Patrick Stuedi
category: blog
comments: true
---

<div style="text-align: justify"> 
<p>
One of the goals of Crail has always been to enable efficient storage disaggregation for distributed data processing workloads. Separating storage from compute resources in a cluster is known to have several interesting benefits. For instance, it allows storage resources to scale independently from compute resources, or to run storage systems on specialized hardware (e.g., storage servers with a weak CPU attached to a fast network) for better performance and reduced cost. Storage disaggregation also simplifies system maintenance as one can uprade compute and storage resources at different cycles. 
</p>
<p>
Today, data processing applications running in the cloud may implicitly use disaggregated storage through cloud storage services like S3. For instance, it is not uncommon for map-reduce workloads in the cloud to use S3 instead of HDFS for storing input and output data. While Crail can offer high-performance disaggregated storage for input/output data as well, in this blog we specifically look at how to use Crail for efficient disaggregation of shuffle data. 
</p>
 
<br>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/disaggregation/spark_disagg.svg" width="580"></div>
<br> 
<br>
 
<p>
Generally, the arguments for disaggregation hold for any type of data including input, output and shuffle data. One aspect that makes disaggregation of shuffle data particularly interesting is that compute nodes generating shuffle data now have access to ''infinitely'' large pools or storage resources, whereas in traditional ''non-disaggregated'' deployments the amount of shuffle data per compute node is bound by local resources.
</p>

<p>
Recently, there has been an increased interest in disaggregating shuffle data. For instance, <a href="https://dl.acm.org/citation.cfm?id=3190534">Riffle</a> -- a research effort driven by Facebook -- is a shuffle implementation for Spark that is capable of operating in a disaggregated environment. Facebook's disaggregated shuffle engine has also been presented at <a href="https://databricks.com/session/sos-optimizing-shuffle-i-o">SparkSummit'18</a>. In this blog, we discuss how Spark shuffle disaggregation is done in Crail using RDMA accessible remote DRAM and NVMe flash. We occasionally also point out certain aspects where our approach differs from Riffle and Facebook's disaggregated shuffle manager. Some of the material shown in this blog has also been presented in previous talks on Crail, namely at <a href="https://databricks.com/session/running-apache-spark-on-a-high-performance-cluster-using-rdma-and-nvme-flash">SparkSummit'17</a> and <a href="https://databricks.com/session/serverless-machine-learning-on-modern-hardware-using-apache-spark">SparkSummit'18</a>. 
</p>
</div>

### Overview

<div style="text-align: justify"> 
<p>
In a traditional shuffle operation, data is exchanged between map and reduce tasks using direct communication. For instance, in a typical Spark deployment map tasks running on worker machines write data to a series of local files  -- one per task and partition -- and reduce tasks later on connect to all of the worker machines to fetch the data belonging to their associated partition. By contrast, in a disaggregated shuffle operation, map and reduce tasks exchange data with each other via a remote shared storage system. In the case of Crail, shuffle data is organized hierarchically, meaning, each partition is mapped to a separate directory (the directory is actually a ''MultiFile" as we will see later). Map tasks dispatch data tuples to files in different partitions based on a key, and reduce tasks eventually read all the data in a given partition or directory (each reduce task is associated with exactly one partition). 
</p>
</div>

<br>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/disaggregation/overview.svg" width="350"></div>
<br>

### Challenge: Large Number of Small Files


<div style="text-align: justify"> 
<p>
One of the challenges with shuffle implementations in general is the large number of objects they have to deal with. The number and size of shuffle files depend on the workload, but also on the configuration, in particular on the number of map and reduce tasks in a stage of a job. The number of tasks in a job is often indirectly controlled through the partition size specifying the amount of data each task is operating on. Finding the optimal partition size for a job is difficult and often requires manual tuning. What you want is a partition size small enough to generate enough tasks to exploit all the parallelism available in the cluster. In theory a small partition size and therefore a large number of small tasks helps to mitigate stragglers, a major issue for distributed data processing frameworks. 
</p>

<p>
Unfortunately, a small partition size often leads to a large number of small shuffle files. As an illustration, we
performed a simple experiment where we measured the size distribution of Spark shuffle (and broadcast) files of individual tasks when executing (a) PageRank on the Twitter graph, and (b) SQL queries on a TPC-DS dataset. As shown in the figure below, the range of shuffle data is large, ranging from a few bytes to a few GBs per compute task.
</p>
</div>

<br>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/disaggregation/cdf-plot.svg" width="480"></div>
<br>

<div style="text-align: justify"> 
<p>
From an I/O performance perspective, writing and reading large numbers of small files is much more challenging than, let's say, dealing with a small number of large files. This is true in a 'non-disaggregated' shuffle operation, but even more so in a disaggregated shuffle operation where I/O requests include both networking and storage.  
</p>
</div> 

### Per-core Aggregation and Parallel Fetching

<div style="text-align: justify"> 
<p>
To mitigate the overheads of writing and reading large numbers of small data sets, the disaggregated Crail shuffler implements two simple optimizations. First, subsequent map tasks running on the same core append shuffle data to a per-core set of files. The number of files in a per-core set corresponds to the number of partitions. Logically, the files in a per core-set are actually part of different directories (one directory per partition as discussed before). For instance, the blue map tasks running on the first core all append their data to the same set of files (marked blue) distributed over the different partitions, same for the light blue and the white tasks. Consequently, the number of files in the system depends on the number of cores and the number of partitions, but not on the number of tasks. 
</p>
</div> 

<br>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/disaggregation/optimization_tasks.svg" width="380"></div>
<br>

<div style="text-align: justify"> 
<p>
The second optimization we use in our disaggregated Crail shuffler is efficient parallel reading of entire partitions using Crail MultiFiles. One problem with large number of small files is that it makes efficient parallel reading difficult, mainly because the small file size limits the number of in-flight read operations a reducer can issue on a single file. One may argue that we don't necessarily need to parallelize the reading of a single file. As long as we have large numbers of files we can instead read different files in parallel. The reason this is inefficient is because we want the entire partition to be available at the reducer in a virtually contiguous memory area to simplify sorting (which is often required). If we were to read multiple files concurrently we either have to temporarily store the receiving data of a file and later copy the data to right place within the contiguous memory area, or, if we want to avoid copying data we can directly instruct the readers to receive the data at the correct offset which leads to random writes and cache thrashing at the reducer. Both, copying data and cache thrashing are a concern at a network speed of 100 Gb/s or more. 
</p>
<p>
Crail Multifiles offer zero-copy parallel reading of large numbers of files in a sequential manner. From the prespective of a map task MultiFiles are flat directories consisting of files belonging to different per-core file sets. From a reducer perspective, a MultFile looks like a large file that can be read sequentially using many in-flight operations. For instance, the following code shows how a reduce task during a Crail shuffle operation reads a partition from remote storage. 
</p>
</div>  
```
CrailStore fs = CrailStore.newInstance();
CrailMultiFile multiFile = fs.lookup("/shuffle/partition1").get().asMultiFile();
ByteBuffer buffer = Buffer.allocateDirect(multiFile.size());
int batchSize = 16;
CrailBufferedInputStream stream = multiFile.getMultiStream(batchSize);
while (stream.read(buf) > 0);
``` 
<div style="text-align: justify"> 
<p>
Internally, a MultiFile manages multiple streams to different files and maintains a fixed number of active in-flight operations at all times (except when the stream reaches its end). The number of in-flight operations is controlled via the batch size parameter which is set to 16 in the above example. 
</p>
<p>
 <strong>Comparison with Riffle</strong>: In contrast to Riffle, the Crail shuffler does not merge files at the map stage. There are two reasons for this. First, even though Riffle shows how to overlap merge operations with map tasks, there is always a certain number of merge operations at the end of a map task that cannot be hidden effectively. Those merge operations delay the map phase. Second, in contrast to Riffle which assumes commodity hardware with low network bandwidth and low metadata throughput (file "open" requests per second), the Crail shuffler is built on top of Crail which offers high bandwidth and high metadata throughput implemented over fast network and storage hardware. As shown in previous posts, Crail supports millions of file metadata operations per second and provides a random read bandwidth for small I/O sizes that is close 100Gb/s. At such a storage performance, any optimization involving the CPU is typically just adding overhead. For instance, the Crail shuffler also does not compress shuffle data as compression rates of common compression libraries (LZ4, Snappy, etc.) are lower than the read/write bandwidth of Crail. 
</p>
<p>
The Crail shuffler also differs from Riffle with regard to how file indexes are managed. Riffle, just like the vanilla Spark shuffler, relies on the Spark driver to map partitions to sets of files and requires reduce tasks to interact with the driver while reading the partitions. In contrast, the Crail shuffler totally eliminates the Spark driver from the loop by encoding the mapping between partitions and files implicitly using the hierarchical namespace of Crail. 
 </p>
</div>  

### Robustness Against Machine Skew

<div style="text-align: justify"> 
<p>
Shuffle operations, being essentially barriers between compute stages, are highly sensitive to task runtime variations. Runtime variations may be caused by skew in the input data which leads to variations in partition size, meaning, different reduce tasks get assigned different amounts of data. Dealing with data skew is tricky and typically requires re-paritioning of the data. Another cause of task runtime variation is machine skew. For example, in a heterogeneous cluster some machines are able to process more map tasks than others, thus, generating more data. In traditional non-disaggregated shuffle operations, machines hogging large amounts of shuffle data after the map phase quickly become the bottleneck (links marked red below) during the all-to-all network transfer phase. 
</p>
</div>
 
<br>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/disaggregation/machine_skew.svg" width="520"></div>
<br>

<div style="text-align: justify"> 
<p>
One way to deal with this problem is through weighted fair scheduling of network transfers, as shown <a href="https://dl.acm.org/citation.cfm?id=2018448">here</a>. But doing so requires global knowledge of the amounts of data to transfer and also demands fine grained scheduling of network transfers. In contrast to a traditional shuffle, the Crail disaggregated shuffler naturally is more robust against machine skew. Even though some machines generate more shuffle data than others during the map phase, the resulting temporary data residing on disaggregated storage is still evenly distributed across storage servers. This is because shuffle data stored on Crail is chopped up into small blocks that get distributed across the servers. Naturally, different storage servers are serving roughly equal amounts of data during the reduce phase. 
 </p>
</div>  

<br>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/disaggregation/machine_skew_crail.svg" width="520"></div>
<br>

<div style="text-align: justify"> 
<p>
One may argue that chopping shuffle data up into blocks and transferring them over the network does not come for free. However, as it turns out, it does almost come for free. The bandwidth of the Spark I/O pipeline in a map task running on a single core is dominated by the serialization speed. The serialization speed depends on the serializer (e.g., Java serializer, Kryo, etc.), the workload and the object types that need to be serialized. In our measurements we found that even for rather simple object types, like byte arrays, the serialization bandwidth of Kryo -- one of the fastest serializers available -- was in the order of a 2-3 Gb/s per core and didn't scale to more than 40 Gb/s aggregated bandwidth on a 16 core machine. The I/O bandwidth in Crail, however, is already at close to 100 Gb/s for a client running on a single core which means that we can write data out to remote storage faster than serialization produces data. In addition, all write (and read) operations in Crail are truly asynchronous and overlap with the map tasks. More precisely, during a map task the RDMA NIC fetches serialized data from host memory and transmits it over the wire while the CPU can continue to serialize the next chunk of data. 
</p>
</div>

<div style="text-align: justify"> 
<p>
<strong>Loadbalancing:</strong> While shuffle disaggregation mitigates machine skew by distributing data evenly across storage servers, the set of storage blocks read by clients (reduce tasks) at a given time may not always be evenly distributed among the servers. For instance, as shown in the figure below (left part), one of the servers concurrently serves two clients, while the other server only serves one client. Consequently, the bandwidth of the first two clients is bottlenecked by the server whereas the bandwidth of last client is not. To mitigate the effect of uneven allocation of bandwidth, it is important to maintain a sufficiently large queue depth (number of in-flight read operations) at the clients. In the example below, a queue depth of two is sufficient to make sure neither of the two clients is bottlenecked by the server (right part in the figure below). 
</p>
</div>

<br>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/disaggregation/loadbalancing.svg" width="520"></div>
<br>

<div style="text-align: justify"> 
<p>
Note that Crail disaggregated storage may be provided by a few highly dense storage nodes (e.g., a high density flash enclosure) or by a larger group of storage servers exposing their local DRAM or flash. We will discuss different deployment modes of Crail disaggregated storage in the next blog post. 
</p>
</div>

### Disaggregated Spark Map-Reduce (Sorting)

<div style="text-align: justify"> 
<p> Let's look at some performance data. In the first experiment we measure the runtime of a simple Spark job sorting 200G of data on a 8 node cluster. We compare the performance of different configurations. In the disaggregated configuration the Crail disaggregated shuffler is used, storing shuffle data on disaggregated Crail storage. In this configuration, Crail is deployed on a 4 node storage cluster connected to the compute cluster over a 100 Gb/s RoCE network. As a direct comparison to the disaggregated configuration we also measure the performance of a co-located setup that also uses the Crail shuffler but deploys the Crail storage platform co-located on the compute cluster. The disaggregated and the co-located configurations are shown for both DRAM only and NVMe only. As a reference we also show the performance of vanilla Spark in a non-disaggregated configuration where the shuffle directory is configured to point to a local NVMe mountpoint.  
 
</p>
</div>

<br>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/disaggregation/terasort.svg" width="450"></div>
<br> 

<div style="text-align: justify"> 
 <p>
The main observation from the figure is that there is almost no performance difference between the Crail co-located and the Crail disaggregated configurations, which means we can disaggregate shuffle data at literally no performance penalty. In fact, the performance improves slightly in the disaggregated configuration because more CPU cycles are available to execute the Spark workload, cycles that in the co-located setup are used for local storage processing. Generally, storing shuffle data in DRAM is about 25% faster than storing shuffle data on NVMe (matching the results of a previous <a href="http://crail.incubator.apache.org/blog/2017/08/crail-nvme-fabrics-v1.html">blog</a>). The effect, however, is independent from whether Crail is deployed in a co-located or in a disaggregated mode. Also note that using the Crail shuffler generally is about 2-3x faster than vanilla Spark, which is the result of faster I/O as well as improved serialization and sorting as discussed in a previous <a href="http://crail.incubator.apache.org/blog/2017/01/sorting.html">blog</a>. 
 </p>
</div>

### Disaggregated Spark SQL

<div style="text-align: justify"> 
 <p>
Next we look at Spark SQL performance in a disaggregated configuration. Again we are partitioning our cluster into two separate silos of compute (8 nodes) and storage (4 nodes), but this time we also investigate the effect of different network speeds and network software stacks when connecting the compute cluster to the storage cluster. The Spark SQL job (TPC-DS, query #87) further differs from the I/O heavy sorting job in that it contains many shuffle phases but each shuffle phase is light on data, thus, stressing latency aspects of shuffle disaggregation more than raw bandwidth aspects. 
</p>
</div>

<br>
<div style="text-align:center"><img src ="{{ site.base }}/img/blog/disaggregation/sql.svg" width="420"></div>
<br> 

<div style="text-align: justify"> 
<p>
The first bar from the left in the figure above shows, as a reference, the runtime of the SQL job using vanilla Spark in a non-disaggregated configuration. Note that the vanilla Spark configuration is using the 100 Gb/s Ethernet network available in the compute cluster. In the next experiment we use the Crail disaggregated shuffler, but configure the network connecting the compute to the storage cluster to be 10 Gb/s. We further use standard TCP communication between the compute nodes and the storage nodes. As one can observe, the overall runtime of this configuration is worse than the runtime of vanilla Spark, mainly due to the extra network transfers required when disaggregating shuffle data. 
</p>
<p>
Often, high network bandwidth is assumed to be the key enabling factor for storage disaggregation. That this is only partially true is shown in the next experiment where we increase the network bandwidth between the compute and the storage cluster to 100 Gb/s, but still use TCP to communicate between compute and storage nodes. As can be observed, this improves the runtime of the SQL job to a point that is almost matching the performance of the non-disaggregated configuration based on vanilla Spark. We can, however, carve out even more performance using the RDMA-based version of the Crail disaggrageted shuffler and get to a runtime that is lower than the one of vanilla Spark in a co-located configuration. One reason why RDMA helps is here because many shuffle network transfers in the Spark SQL workload are small and the Crail RDMA storage tier is able to substantially reduce the latencies of these transfers. 
 </p>
</div>


### Summary

Efficient disaggregation of shuffle data is challenging, requiring shuffle managers and storage systems to be co-designed in order to effectively handle large numbers of small files, machine skew and loadbalancing issues. In this blog post we discussed the basic architecture of the Crail disaggregated shuffle engine and showed that by using Crail we can effectively disaggregate shuffle data in both bandwidth intensive map-reduce jobs as well as in more latency sensitive SQL workloads. In the next blog post we will discuss several deployment options of disaggregated storage in a tiered storage environment. 


