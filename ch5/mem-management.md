## 内存管理学习
- 主要是分为两个部分,内存分配和内存回收.rust 牛逼~
- 垃圾回收算法与实现 必读
- 垃圾回收算法手册 必读
- 知道 [tcmalloc](https://google.github.io/tcmalloc/overview.html) [jemalloc](http://jemalloc.net/) 这些内存回收库
- 知道 mmap 系统调用,可以把 Unix 系统中的 文件 I/O设备 堆内存映射到物理地址上,这样 CPU 就能直接访问了
- 堆内存从操作系统来,brk 和 mmap brk 用于 小于 128k 连续堆内存申请,大于 128k 的用 mmap.brk 能根据大小算出内存块的终点,
mmap 可以指定起点和终点.
- 要知道内存是分配在栈上的还是堆上的. 这个需要自己理一遍,通过 go 的 escap testcase 或者读代码都 OK. 起码我们知道函数返回
一个局部变量的指针那必须发生逃逸. 如果是内联了. 可能在就立刻展开了.就不一定逃逸.逃逸就是内存对象从栈上被编译器搞到堆上的
的一种机制. 其实通过对象生命周期分析还是很简单的. 主要是从 内存安全, 栈的大小限制等决定是否要逃逸.

## 对分配代码流程简单梳理
- runtime.newobject 只要分配堆内存就会用到.
- newobject 调用 mallocgc() 

`func mallocgc(size uintptr, typ *_type, needzero bool) unsafe.Pointer`
第一个参数说我要多少内存, 第二个说这段空间要存放的数据类型.返回一个这段内存地址的起始位置的指针.

如果是零大小类型. 如空 struct{} 他们直接返回一个特定的地址.

然后锁住当前 m, 然后通过 getMCache 函数 找到 p 对应的 mcache. 这个函数会判断一下是否是初始化阶段调用,(没有P 的情况)
返回 mcache 的地址.

go 拿到的堆内存被分为 多个 arena 一个 arena 64M  arena 被分为 8192 个大小为 8K 的 page, 这些 page 通过组合成为大小不同
span span 的种类通过 spanclass 描述, 根据大小分为 68 个,根据是否包含指针 noscan 所以一共有 68 * 2 种 spanclass 