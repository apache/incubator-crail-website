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

### Crail Metadata Operation overview

<div style="text-align: justify"> 
<p>
As described in <a href="/blog/2017/08/crail-memory.html">part I</a>, Crail data operations are composed of actual data transfers and metadata operations. Metadata operations includes looking up block information, such as on which datanode a block is stored, file attributes and filename to data block mapping. Every client will execute a certain amount of metadata operations to create files, find file data blocks, modify or delete files. This blog is about measuring metadata operation characteristics and metadata operation performance.
</p>
</div>
<br>
<div style="text-align:center"><img src ="http://crail.io/img/blog/crail-metadata/rpc.png" width="420"></div>
<br>

<div style="text-align: justify"> 
<p>
Metadata operations are performed using RPCs. RPCs are small-sized request packets sent over the network followed by small-sized replies sent back to the requestor. On RDMA networks, send and receives are used for RPCs (basically post send and post receive). These operations are implemented based on <a href="http://github.com/zrlio/darpc">DaRPC</a>
and <a href="http://github.com/zrlio/disni">DiSNI</a>, where DiSNI offers a VERBS API for Java and DaRPC offers a more highlevel framework to build RDMA-based RPC servers and clients.
</p>
<p>
As every network operation, two ways of implementation of RPCs are possible: Blocking synchronous RPCs and non-blocking asynchronous RPCs. The namenode offers both implementations at the client side, therefore the client can chose whether to block and wait for the RPC reply or whether to do some work and asyncrhonously receive the reply.
</p>
</div>

### What measurements matter for metadata operations?
Before measuring metadata characteristics, we need to decide what metrics
to use and what measurements to make.
When it comes to measurements in networks, the first two ideas are probably
bandwidth and latency. While this are important values for data transfers,
there is another metric, especially for small-sized RPC operations, which
matters.
An RPC server mostly needs to be able to process a high number of
RPCs per second, while the actual bandwidth does not matter too much for small
RPCs. The number of RPCs, which can be processed per second, is
basically the number of I/O operations, which can be executed per second
and is often reffered to as IOPS.

Given that every client will execute a certain amount of metadata operations
(see above), every client adds a certain number of additional RPCs that
need to be performed by the system. In other words, the higher the number
of IOPS the system can handle, the more client can concurrently use
Crail without performance loss at the RPC level (RPC is not the bottleneck).

### Namenode metadata operations
Metadata operations are mostly executed at the namenodes. Namenodes are
responsible to store information about files and data blocks. Namenodes
offer an RPC-based API to query such information.

Namenodes need to be able to process a high amount of IOPS to ensure that
they do not become the bottleneck of the overall system.

An often used metadata operation is the ''getFile()'' RPC call, which
looksup file information. The client calls ''getFile()'', which causes
and RPC request to the namenode. The namenode sends back an RPC reply to the
client.

The client has the choice of using the blocking ''getFile()'' implementation
or the non-blocking asynchronous ''getFileAsync()'' implementation.

In this experiment the goal is to measure the achievable IOPS on the server
side. We use the asynchronous ''getFileAsync()'' operation on the client side
to ensure that the client is not the bottleneck. The client sends a maximum
of 128 outstanding ''getFileAsync()'' RPCs. As soon as the client
receives the RPC reply, it matches it with the original request in its
pending operations data structures and frees this request from its data
structure. This is what a regular client would do (so we do not just send
requests without processing the replies).

At the namenode side it does not matter, which implementation the client
uses. For the namenode it is the same operation ''getFile()'', which causes
it to lookup information about the file and sending back a reply.


In the first experiment, we use a single namenode instance. The namenode runs
on 8 physical cores (no hyperthreading).
Clients execute ''getFileAsync()'' operations
in a thight loop. The namenode measures the aggregated number of
RPCs it can handle per second. The results are shown in the first graph below,
labelled ''Namenode IOPS''.

The namenode only gets saturated with more than 16 clients. The graph shows
that the namenode can handle close to 10 million ''getFile()'' operations
per second. With significantly more clients, the overall number of IOPS
drops slightely, as more resources are being allocated on the single
RDMA card, which basically creates a contention on hardware resources.

As comparison, we measure the raw number of IOPS, which can be executed
on the RDMA network. We measure the raw number using ib_send_bw.
We configured ib_send_bw with the same parameters in terms of RDMA configuration
as the namenode. This means, we instructed ib_send_bw not to do CQ moderation,
and to use a receive queue and a send queue of length 32, which
equals the length of the namenode queues. Note that the default
configuration of ib_send_bw uses CQ moderation and does preposting of send
operations, which can only be done, if the operation is known in advance.
This is not the case in a real system, like crail's namenode.

The line of the raw number of IOPS, labelled ''ib send'' is shown in the same
graph. With this measurement we show that Crail's namenode IOPS are similar
to the raw ib_send_bw IOPS with the same configuration.

<div style="text-align:center"><img src ="/img/blog/crail-metadata/namenode_ibsend_iops64.svg" width="550"/></div>

If one starts ib_send_bw without specifying the queue sizes or whether or not
to use CQ moderation, the raw number of IOPS might be higher. This is
due to the fact, that the default values of ib_send_bw use a receive queue of
512, a send queue of 128 and CQ moderation of 100, meaning that a new
completion is generated only after 100 sends. As comparison, we did this
measurement too and show the result, labelled 'ib_send CQ mod',
in the same graph. Fine tuning of receive and send queue sizes, CQ moderation
size, podstlists etc might lead to a higher number of IOPS.


### Namenode scalability
To increase the number of IOPS the overall system can handle, we allow
starting multiple namenode instances. Hot RPC operations, such as
''getFile()'', are distributed over all running instances of the namenode.
''getFile()'' is implemented such that no synchronization among the
namenodes is required. As such, we expect good scalability.


For the following experiment, every client executes ''getFile()'' operations
in a tight loop as above. The graph below compares the overall IOPS of a system
with one namenode to a system with two namenodes.

<div style="text-align:center"><img src ="/img/blog/crail-metadata/namenode_multi64.svg" width="550"/></div>


We show in this graph that the system can handle around 17Mio IOPS with
two namenodes. Having multiple namenode instances matters especially with
a higher number of clients. In the graph we see that the more clients we
have the more we can benefit from a second namenode instance.

### Summary
In this blog we show that Crail's namenode is able the handle a big number
of IOPS. Crail's namenode performs similarly to the raw number of IOPS measured
using ib_send_bw, when configured with the same parameters. This shows that
the actual processing of the RPC is implemented efficiently.

In addition, the namenode scales well in terms of number of
instances. This allows to deploy Crail on a larger cluster with many
clients.

