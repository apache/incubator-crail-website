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
  * 4x 512 GB Samsung 960Pro NVMe SSDs (512Byte sector size, no metadata)
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
We perform latency and throughput measurement of our Crail NVMf storage tier against a native SPDK NVMf benchmark to determine how much overhead our implementation adds. The first plot shows random read latency on a single 512GB Samsung 960Pro accessed remotely through SPDK. For Crail we also show the time it takes to perform a metadata operations. You can run the Crail benchmark from the command line like this:
```
./bin/crail iobench -t readRandomDirect -s <size> -k <iterations> -w 32 -f /tmp.dat
```
and SPDK:
```
./perf -q 1 -s <size> -w randread -r 'trtype:RDMA adrfam:IPv4 traddr:<ip> trsvcid:<port>' -t <time in seconds>
```
The main take away from this plot is that the time it takes to perform the actual data operation (not considering the time it takes to perform the metadata operation) our NVMf storage tier implementation is very close to the native SPDK performance and only adds a few 100ns of overhead. Remember, Crail is written in Java and every data operation is a JNI operation leaving the JVM to call the appropriate SPDK function. Also keep in mind that this an extrem case where no metadata is cached and in typical applications metadata is prefetched.

<div style="text-align:center"><img src ="http://crail.io/img/blog/crail-nvmf/latency.svg" width="550"/></div>

The second plot shows sequential read and write throughput with a transfer size of 64KB and 128 outstanding operations. The Crail throughput benchmark can be run like this:
```
./bin/crail iobench -t readAsync -s 65536 -k <iterations> -b 128 -w 32 -f /tmp.dat
```
and SPDK:
```
./perf -q 128 -s 65536 -w read -r 'trtype:RDMA adrfam:IPv4 traddr:<ip> trsvcid:<port>' -t <time in seconds>
```
Here the metadata information can be easliy prefetch due to the sequential access and a single operation is long enough to allow the metadata prefetch to finish before the next operation begins. This allows our NVMf storage tier to reach the same throughput as the native SPDK benchmark (device limit).

<div style="text-align:center"><img src ="http://crail.io/img/blog/crail-nvmf/throughput.svg" width="550"/></div>

### Sequential Throughput
Let us look at the sequential read and write throughput for buffered and direct streams and compare them to a buffered Crail stream on DRAM. All benchmarks are single thread/client performed on 8 storage tiers with 4 drives each, cf. configuration above. In this benchmark we use 32 outstanding operations for the NVMf storage tier buffered stream experiments by using a buffer size of 16MB and a slice size of 512KB, cf. <a href="http://www.crail.io/blog/2017/07/crail-memory.html">part I</a>. The buffered stream reaches line speed at a transfer size of around 1KB and shows only slightly slower performance when compared to the DRAM tier buffered stream. However we are only using 2 outstanding operations with the DRAM tier to achieve these results. Basically for sizes smaller than 1KB the buffered stream is limited by the copy speed to fill the application buffer. The direct stream reaches line speed at around 128KB with 128 outstanding operations. Here no copy operation is performed for transfer size greater than 512Byte (sector size). The command to run the Crail buffered stream benchmark:
```
./bin/crail iobench -t readSequentialHeap -s <size> -k <iterations> -w 32 -f /tmp.dat
```
The direct stream benchmark:
```
./bin/crail iobench -t readAsync -s <size> -k <iterations> -b 128 -w 32 -f /tmp.dat
```

<div style="text-align:center"><img src ="http://crail.io/img/blog/crail-nvmf/throughput2.svg" width="550"/></div>

### Random Read Latency
Random read latency is limited by flash technology and we currently see around 70microseconds when performing sector size accesses to the device with Crail. Remote DRAM latencies with Crail are around 7-8x faster than our NVMf tier however we believe that this will change in the near future with new technologies like PCM. Intel's Optane drives already can deliver random read latencies of around 10microseconds. Considering that there is an overhead of around 10microseconds to access a drive with Crail using such a device would put random read latencies somewhere around 20microseconds which is only half the performance of our DRAM tier.

<div style="text-align:center"><img src ="http://crail.io/img/blog/crail-nvmf/latency2.svg" width="550"/></div>

### Tiering DRAM - NVMf
In this paragraph we show how Crail can leverage flash memory when there is too little or no DRAM to hold all your data available while only seeing a minor performance decrease in (most) real world applications. If you have multiple tiers deployed in Crail, e.g. the DRAM tier and the NVMf tier. Crail first uses up all available resources of the faster tier even if it is a remote resource because the faster tier accessed remotely is typically still faster than the slower tier's local resource. This is what we call horizontal tiering. In the following experiment we gradually artificially limit DRAM resources to leverage more and more flash memory in a Spark/Crail Terasort application. We sort 200GB of data and reduce memory in 20% steps from all data in memory to all data in flash. The plot shows that by putting all the data in flash we only reduce the sorting time by around 48%. Considering the cost of DRAM and the advances in technology described above we believe cheaper NVM storage can replace DRAM for most of the applications with only a minor performance decrease.

