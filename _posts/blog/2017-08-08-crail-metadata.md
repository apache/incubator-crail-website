---
layout: post
title: "Crail Storage Performance -- Part III: Metadata (Draft)"
author: Adrian Schuepbach
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
  * 8 node OpenPower cluster
* Node configuration
  * CPU: 2x OpenPOWER Power8 10-core @2.9Ghz
  * DRAM: 512GB DDR4
  * 4x 512 GB Samsung 960Pro NVMe SSDs (512Byte sector size, no metadata)
  * Network: 1x100Gbit/s Mellanox ConnectX-4 IB
* Software
  * RedHat 7.3 with Linux kernel version 3.10
  * Crail 1.0, internal version 2842
  * SPDK git commit 5109f56ea5e85b99207556c4ff1d48aa638e7ceb with patches for POWER support
  * DPDK git commit bb7927fd2179d7482de58d87352ecc50c69da427

### Anatomy of a Crail Metadata Operation

