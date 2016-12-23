---
layout: default
title: "Software Overheads"
author: someone
category: blog
---

<div style="text-align: justify"> 
<p>
Retaining the hardware performance in a distributed setting where DRAM and flash resources are accessed over a fast network is challenging. The figure below shows the network throughput of a shuffle operation in a simple Spark sorting workload on a 100Gb/s cluster. Note that during this mapreduce job, a reduce task needs to first fetch all the relevant data from the network before it can start sorting the data. Despite the urgent need to fetch data as fast as possible, the network usage stays at only 5-10%. 
</p>
</div>

![vanilla_net](https://patrickstuedi.github.io/website/docs/net_vanilla.svg)

<div style="text-align: justify">
<p>
In fact, making good use of a high-speed network is challenging for many of the prominent data processing frameworks and workloads. While commonly a network upgrade from 1Gb/s to 10Gb/s leads to a reduction of the application runtime, further network upgrades to 40Gb/s or even 100Gb/s (not shown) do not translate into performance improvements at all.
</p>
</div>

<img src="https://patrickstuedi.github.io/website/docs/net_apache.png" width="600">
