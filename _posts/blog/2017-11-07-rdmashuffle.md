---
layout: post
title: "Crail Storage Performance -- Part III: Metadata (Draft)"
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
  * Crail 1.0, internal version 2993

