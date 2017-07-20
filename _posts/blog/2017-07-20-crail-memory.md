---
layout: post
title: "Crail Storage Performance -- Part I: DRAM (Draft)"
author: Patrick Stuedi
category: blog
comments: true
---

<div style="text-align: justify"> 
<p>
This is the first of three blog posts illustrating Crail's raw storage performance. In part I we cover Crail's DRAM storage tier, part II will be about Crail's NVMe flash storage tier, and part III will be about Crail's metadata performance. 
</p>
</div>

### Hardware Configuration

The specific cluster configuration used for the experiments in this blog:

* Cluster
  * 8 node OpenPower cluster
* Node configuration
  * CPU: 2x OpenPOWER Power8 10-core @2.9Ghz
  * DRAM: 512GB DDR4
  * Network: 1x100Gbit/s Ethernet Mellanox ConnectX-4 EN (RoCE)
             1x100Gbit/s Infiniband Mellanox ConnectX-4 EN
* Software
  * RedHat 7.2 with Linux kernel version 4.10.13
  * Crail 1.0, internal version 2842

