---
layout: post
title: "Crail Storage Performance -- Part II: NVMe Flash (Draft)"
author: Jonas Pfefferle
category: blog
comments: true
---

<div style="text-align: justify"> 
<p>
This is part II of our series of posts discussing Crail's raw storage performance. This part is about Crail's NVMe storage tier, a low-latency flash storage backend for Crail completely based on user-level storage access. 
</p>
</div>

### Hardware Configuration

The specific cluster configuration used for the experiments in this blog:

* Cluster
  * 8 node OpenPower cluster
* Node configuration
  * CPU: 2x OpenPOWER Power8 10-core @2.9Ghz
  * DRAM: 512GB DDR4
  * 2x 1.2 TB NVMe SSDs
  * Network: 1x100Gbit/s Ethernet Mellanox ConnectX-4 EN (Ethernet/RoCE)
* Software
  * RedHat 7.2 with Linux kernel version 4.10.13
  * Crail 1.0, internal version 2842
  * Alluxio 1.4
  * RAMCloud commit f53202398b4720f20b0cdc42732edf48b928b8d7

### Anatomy of a Crail NVM Operation

