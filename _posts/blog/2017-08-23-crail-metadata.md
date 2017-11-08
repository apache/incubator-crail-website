---
layout: post
title: "Crail Storage Performance -- Part III: Metadata (Draft)"
author: Adrian Schuepbach and Patrick Stuedi
category: blog
comments: true
---

<div style="text-align: justify">
<p>
This is part III of our series of posts discussing Crail's raw storage performance. This part is about Crail's metadata performance and scalability.
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
  * Crail 1.0, internal version 2993

### Crail Metadata Operation Overview

<div style="text-align: justify"> 
<p>
As described in <a href="/blog/2017/08/crail-memory.html">part I</a>, Crail data operations are composed of actual data transfers and metadata operations. Examples of metadata operations are operations for creating or modifying the state of a file, or operations to lookup the storage server that stores a particular range (block) of a file. In Crail, all the metadata is managed by the namenode(s) (as opposed to the data which is managed by the storage nodes). Clients interact with Crail namenodes via Remote Procedure Calls (RPCs). Crail supports multiple RPC protocols for different types of networks and also offers a pluggable RPC interface so that new RPC bindings can be implemented easily. On RDMA networks, the default <a href="http://github.com/zrlio/darpc">DaRPC</a> based RPC binding provides the best performance. The figure below gives an overview of the Crail metadata processing in a DaRPC configuration. 
</p>
</div>

<div style="text-align:center"><img src ="http://crail.io/img/blog/crail-metadata/rpc.png" width="480"></div>
<br>

<div style="text-align: justify"> 
<p>
Metadata operations issued by clients are hashed to a particular namenode depending on the name of object the operation attempts to create or retrieve. With the DaRPC binding, RPC messages are exchanged using RDMA send/recv operations. At the server, RPC processing is parallelized across different cores. To minimize locking and cache contention, each core handles a disjoint set of client connections. Connections assigned to the same core share the same RDMA completion queue which is processed exclusively by that given core. All the network queues, including send-, recv- and completion queues are mapped into user-space and accessed directly from within the JVM process. Since Crail offers a hierarchical storage namespace, metadata operations to create, delete or rename new storage resources effectively result in modifications to a tree-like data structure at the namnode. These structural operations require a somewhat more expensive locking than the more lightweight operations used to lookup the file status or to extend a file with a new storage block. Consequently, Crail namenodes use two separate data structures to manage metadata: (a) a basic tree data structure that requires directory-based locking, and (b) a fast lock-free map to lookup of storage resources that are currently being read or written.
</p>
</div>

### Experimental Setup

<div style="text-align: justify"> 
<p>
In two of the previous blogs (<a href="/blog/2017/08/crail-memory.html">DRAM</a>,<a href="/blog/2017/08/crail-nvme-fabrics-v1.html">NVMf</a>) we have already shown that Crail metadata operations are very low latency. Essentially a single metadata operation issued by a remote client takes 5-6 microseconds, which is only slightly more than the raw network latency of the RDMA network fabric. In this blog, we want to explore the scalability of Crail's metadata management, that is, the number of clients Crail can support, or how Crail scales as the cluster size increases. The level of scability of Crail is mainly determined by the number of metadata operations Crail can process concurrently, a metric that is often reffered to as IOPS. The higher the number of IOPS the system can handle, the more clients can concurrently use Crail without performance loss. 
</p>
<p>
An important metadata operation is ''getFile()'' which is used by clients to lookup the status of a file (whether the file exists, what size it has, etc.). The ''getFile()'' operation is served by Crail's fast lock-free map and in spirit is very similar to the ''getBlock()'' metadata operation. In a typical Crail use case, ''getFile()'' and ''getBlock()'' are responsible for the peak metadata load at a namenode. In this experiment, we measure the achievable IOPS on the server side in an artificial configuration with many clients distributed across the cluster issuing ''getFile()'' in a tight loop. Note that the client side RPC interface in Crail is asynchronous, thus, clients can issue multiple metadata operations without blocking while asynchronously waiting for the result. In the experiments below, each client may have a maximum of 128 ''getFile()'' operations outstanding at any point in time. In a practical scenario, Crail clients may also have multiple metadata operations in flight either because clients are shared by different cores, or because Crail interleaves metadata and data operations (see <a href="/blog/2017/08/crail-memory.html">DRAM</a>). What makes the benchmark artificial is that clients exclusively focus on generating load for the namenode and thereby are neither performing data operations nor are they doing any compute. The basic command of the benchmark as executed by each of the individual clients is given by the following command:
</p>
</div>
```
./bin/crail iobench -t getFileAsync -f /tmp.dat -k 1000000 -b 128
```   

### Single Namenode Scalability

<div style="text-align: justify"> 
<p>
In the first experiment, we measure the aggregated number of metadata operations a single Crail namenode can handle per second. The namenode runs on 8 physical cores with hyperthreading disabled. The result is shown in the first graph below, labelled ''Namenode IOPS''. The namenode only gets saturated with more than 16 clients. The graph shows that the namenode can handle close to 10 million ''getFile()'' operations per second. With significantly more clients, the overall number of IOPS drops slightely, as more resources are being allocated on the single RDMA card, which basically creates a contention on hardware resources.
</p>
<p> 
As comparison, we measure the raw number of IOPS, which can be executed on the RDMA network. We measure the raw number using ib_send_bw. We configured ib_send_bw with the same parameters in terms of RDMA configuration as the namenode. This means, we instructed ib_send_bw not to do CQ moderation, and to use a receive queue and a send queue of length 32, which equals the length of the namenode queues. Note that the default configuration of ib_send_bw uses CQ moderation and does preposting of send operations, which can only be done, if the operation is known in advance. This is not the case in a real system, like crail's namenode. The line of the raw number of IOPS, labelled ''ib send'' is shown in the same graph. With this measurement we show that Crail's namenode IOPS are similar to the raw ib_send_bw IOPS with the same configuration.
</p>
</div>
<br>
<div style="text-align:center"><img src ="/img/blog/crail-metadata/namenode_ibsend_iops64.svg" width="550"/></div>
<br>
<div style="text-align: justify"> 
<p>
If one starts ib_send_bw without specifying the queue sizes or whether or not to use CQ moderation, the raw number of IOPS might be higher. This is due to the fact, that the default values of ib_send_bw use a receive queue of 512, a send queue of 128 and CQ moderation of 100, meaning that a new completion is generated only after 100 sends. As comparison, we did this
measurement too and show the result, labelled 'ib_send CQ mod', in the same graph. Fine tuning of receive and send queue sizes, CQ moderation size, postlists etc might lead to a higher number of IOPS. 
</p>
</div>

### Multiple Namenode Scalability

<div style="text-align: justify"> 
<p>
To increase the number of IOPS the overall system can handle, we allow starting multiple namenode instances. Hot metadata operations, such as ''getFile()'', are distributed over all running instances of the namenode. ''getFile()'' is implemented such that no synchronization among the namenodes is required. As such, we expect good scalability. The graph below compares the overall IOPS of a system with one namenode to a system with two namenodes.
</p>
</div>
<br>
<div style="text-align:center"><img src ="/img/blog/crail-metadata/namenode_multi64.svg" width="550"/></div>
<br>

<div style="text-align: justify"> 
<p>
We show in this graph that the system can handle around 17Mio IOPS with two namenodes. Having multiple namenode instances matters especially with a higher number of clients. In the graph we see that the more clients we have the more we can benefit from a second namenode instance.
</p>
</div>

### Cluster sizes

<div style="text-align: justify"> 
<p>
Let us look at a concrete application, which ideally runs on a large cluster:
TeraSort. In a previous blog, <a href="/blog/2017/01/sorting.html">sorting</a>,
we analyze performance characteristics of TeraSort on Crail on a big cluster
of 128 nodes, where we run 384 executors in total. This already proves that
Crail can at least handle 384 clients. Now we analyze the theoretical number
of clients without performance loss at the namenode. Still this theoretical
number is not a hard limit on the number of clients. Just adding more
clients would start dropping the number of IOPS per client (not at the
namenode).
</p>
</div>

<div style="text-align: justify"> 
<p>
In contrast to the benchmarks above, a real-world application, like TeraSort,
does not issue RPC requests in a tight loop. It rather does sorting
(computation), file reading and writing and and of course a certain amount of
RPCs to manage the files.
</p>
</div>

<div style="text-align: justify"> 
<p>
We would like to know how many RPCs a run of TeraSort generates and therefore
how big the load in terms of number of IOPS is at the namenode for a
real-world application.
We run TeraSort on a data set of 200GB and measured the
number of IOPS at the namenode with 4 executors, 8 executors and 12 executors.
Every executor runs 12 cores. For this experiment, we use a single namenode
instance. We plot the distribution of the number of IOPS measured at the
namenode over the ellapsed runtime of the TeraSort application.
</p>
</div>

<br>
<div style="text-align:center"><img src ="/img/blog/crail-metadata/terasort_iops.svg" width="550"/></div>
<br>


<div style="text-align: justify"> 
<p>
From the graph we pick the peak number of IOPS measured
throughout the execution time for all three cases. The following table
shows the three peak IOPS numbers:
</p>
</div>

<br/>
<center>
<table>
  <thead>
    <tr>
      <th>Number of executor nodes</th>
      <th>IOPS at namenode for TeraSort<br/>(measured)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="right">4</td>
      <td align="right">31573.00</td>
    </tr>
    <tr>
      <td align="right">8</td>
      <td align="right">66618.38</td>
    </tr>
    <tr>
      <td align="right">12</td>
      <td align="right">107305.00</td>
    </tr>
  </tbody>
</table>
</center>
<br/>

<div style="text-align: justify"> 
<p>
From this table we see that it scales linearly. Even more important,
we notice that with 12 nodes we still use only around 1% of the
number of IOPS a single namenode can handle.
If we plot this to the measured maximum amount of around 10 Mio IOPS
per namenode (see above), we see immediately that the namenode can handle
way more clients:
</p>
</div>

<br>
<div style="text-align:center"><img src ="/img/blog/crail-metadata/terasort_namenode_iops.svg" width="550"/></div>
<br>

<div style="text-align: justify"> 
<p>
If we extrapolate this to a
100%, we can handle a cluster size of almost 1200 nodes (1118 clients being just
below 10Mio IOPS at the namenode). The
extrapolated numbers would look like this:
</p>
</div>


<br/>
<center>
<table>
  <thead>
    <tr>
      <th>Number of executor nodes</th>
      <th>IOPS at namenode for TeraSort<br/>(extrapolated)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="right">4</td>
      <td align="right">31573.00</td>
    </tr>
    <tr>
      <td align="right">8</td>
      <td align="right">66618.38</td>
    </tr>
    <tr>
      <td align="right">12</td>
      <td align="right">107305.00</td>
    </tr>
    <tr>
      <td align="right">...</td>
      <td align="right">...</td>
    </tr>
    <tr>
      <td align="right">1118</td>
      <td align="right">9997249.00</td>
    </tr>
    <tr>
      <td align="right">...</td>
      <td align="right">...</td>
    </tr>
    <tr>
      <td align="right">1200</td>
      <td align="right">10730500.00</td>
    </tr>
  </tbody>
</table>
</center>
<br/>

<div style="text-align: justify"> 
<p>
Of course we know that there is no system with perfect linear scalability.
But even if we would loose 50% of the number of IOPS (compared to the
theoretical maximum) on a big cluster, Crail could still handle a cluster size
of 600 nodes and a single namenode without any performance loss at the
namenode.
Should we still want to run an application like TeraSort on a bigger cluster,
we can add a second namenode or have even more instances of namenodes
to ensure that clients do not suffer from contetion in terms of IOPS at
the namenode.
</p>
</div>


<div style="text-align: justify">
<p>
We believe that the combination of benchmarks above, the scalability
experiments and the real-world
application of TeraSort shows clearly that Crail and Crail's namenode can handle
a big cluster of at least several hundreds of nodes, theoretically up to
1200 nodes with a single namenode and even more with multiple namenodes.
</p>
</div>

### Summary

<div style="text-align: justify"> 
<p>
In this blog we show that Crail's namenode is able the handle a big number
of IOPS. Crail's namenode performs similarly to the raw number of IOPS
measured using ib_send_bw, when configured with the same parameters. This
shows that the actual processing of the RPC is implemented efficiently.
In addition, the namenode scales well in terms of number of
instances. This allows to deploy Crail on a larger cluster with many
clients.
</p>
</div>

<div style="text-align: justify"> 
<p>
With TeraSort as real application, we show that in real-world scenarios
Crail supports big clusters with several hundred of clients.
</p>
</div>

