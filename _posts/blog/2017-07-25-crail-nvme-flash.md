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
  * 4x 512 GB Samsung 960Pro NVMe SSDs
  * Network: 1x100Gbit/s Mellanox ConnectX-4 IB
* Software
  * RedHat 7.3 with Linux kernel version 3.10
  * Crail 1.0, internal version 2842
  * SPDK git commit 5109f56ea5e85b99207556c4ff1d48aa638e7ceb with patches for POWER support
  * DPDK git commit bb7927fd2179d7482de58d87352ecc50c69da427

### Anatomy of a Crail NVM Operation
Due to the modular design of Crail implementing a new storage tier is fairly easy. All metadata operations as explained in <a href="http://www.crail.io/blog/2017/07/crail-memory.html">part I</a> of this series are taken care of by the namenode resp. its (plugable) RPC implementation. As a storage tier we are responsible in a) donating regions of our memory resource to the namenode and b) performing data operations on them. In our NVMf storage tier each server process manages exactly one NVMe drive and is responsible for a) and the server side of b). To achieve the best performance we wanted to use a user-level implemention to access the NVMe drives and transfer the data over the network. We opted for the <a href="http://www.spdk.io">Storage Performance Developer Kit (SPDK)</a> as it is a widely used open-source project. The serve side of our NVMf storage tier sets up a NVMf target through SPDK and donates memory regions (basically splits up the NVMe namespaces into smaller blocks) to the namenode which are identified by ip, port, key and an offset. The namenode then splits up all regions into blocks, the smallest entity in Crail which composes every file. Whenever a data operation is performed the client fetches the metadata information for a particular block from the namenode which contains the identifier. With this information our NVMf storage tier client implementation is able to connect to the appropriate NVMf target and performs data operations on it through SPDK.

One downside of using a raw storage interface like NVMe is that they do not allow for byte level access but instead you have to issue data operations on drive sectors which are typically 512Byte or 4KB large. As we wanted to use the standard NVMf protocol (and Crail has a client driven philosophy) we needed to implement byte level access on the client side. For reads this can be implemented in a straight forward way by reading the whole sector and copying out the needed part. For writes that modify a sector which has already been written before we need to do a read modify write operation.

### Performance comparison to native SPDK NVMf

<div style="text-align:center"><img src ="http://crail.io/img/blog/crail-nvmf/latency.svg" width="550"/></div>
<div style="text-align:center"><img src ="http://crail.io/img/blog/crail-nvmf/throughput.svg" width="550"/></div>

### Sequential Throughput

<div style="text-align:center"><img src ="http://crail.io/img/blog/crail-nvmf/throughput2.svg" width="550"/></div>

### Random Read Latency

<div style="text-align:center"><img src ="http://crail.io/img/blog/crail-nvmf/latency2.svg" width="550"/></div>

