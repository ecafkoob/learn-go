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

真正决定 arena 大小的是 heapArenaBytes 这个东西. 这个东西与系统的位数和

mheap 全局唯一:
arenas [1]*[1<<22]*heapArena

heapArena:

mspan:

mcache: 每个 P 都有一个 mcache 字段. 分配小对象 优先从 P 本地获取. 

mheap.central:

spanClass: 用一个 uint8 数表示, 包含 sizeclass 索引. 和 是否扫描的标志位. 这个数 >> 右移一位
获得 sizeclass idx, 最后一位如果是 1 表示 noscan 0 表示需要 scan.

mem_${OS}.go 文件定义了平台相关的内存操作, 比如 Unix 系的 mmap munmap 之类的. 这是go runtime 向操作系统要内存的
最开是的地方.

Q: 看一下 golang 是怎么使用 mmap 系统调用来找系统要内存的? 
A: 就以 sysAlloc 为例, 他调用了go 定义的平台相关的内存分配系统调用. 一般是 mmap 这是一个 go 函数.通过 libcall 调用
mmap_trampoline 这个只有函数名的函数 那说明他的实现应该是汇编. 这个 `func mmap(addr uintptr, length uintptr, prot int, flag int, fd int, pos int64) (ret uintptr, err error)`
这个函数通过 syscall_syscall6 这个 syscall 调用的封装函数 libc_mmap_trampoline, 其定义在
```asm
TEXT libc_mmap_trampoline<>(SB),NOSPLIT,$0-0
	JMP	libc_mmap(SB)
```
简单看下 mmap 的参数:
```asm
       PROT_EXEC  Pages may be executed.
       
       PROT_READ  Pages may be read.

       PROT_WRITE Pages may be written.

       PROT_NONE  Pages may not be accessed.
       
       MAP_PRIVATE
              Create a private copy-on-write mapping.  Updates to the mapping are not visible to other processes mapping the same file, and are not carried through to the underlying file.  It is unspec-
              ified whether changes made to the file after the mmap() call are visible in the mapped region.
              
       MAP_ANON
              Synonym for MAP_ANONYMOUS; provided for compatibility with other implementations.
              
       MAP_FIXED
              Don't  interpret  addr as a hint: place the mapping at exactly that address.  addr must be suitably aligned: for most architectures a multiple of the page size is sufficient; however, some
              architectures may impose additional restrictions.  If the memory region specified by addr and len overlaps pages of any existing mapping(s), then the overlapped part of the  existing  map-
              ping(s) will be discarded.  If the specified address cannot be used, mmap() will fail.

              Software  that  aspires  to  be  portable  should  use the MAP_FIXED flag with care, keeping in mind that the exact layout of a process's memory mappings is allowed to change significantly
              between kernel versions, C library versions, and operating system releases.  Carefully read the discussion of this flag in NOTES!
```
就通过 mmap 完成了内存的获取.

有了获取就要有归还. munmap 就是干这个事情的.

下面就是 go 和操作系统之间的内存管理的接口了.

```md
// OS memory management abstraction layer
//
// Regions of the address space managed by the runtime may be in one of four
// states at any given time:
// 1) None - Unreserved and unmapped, the default state of any region.
// 2) Reserved - Owned by the runtime, but accessing it would cause a fault.
//               Does not count against the process' memory footprint.
// 3) Prepared - Reserved, intended not to be backed by physical memory (though
//               an OS may implement this lazily). Can transition efficiently to
//               Ready. Accessing memory in such a region is undefined (may
//               fault, may give back unexpected zeroes, etc.).
// 4) Ready - may be accessed safely.
//
// This set of states is more than is strictly necessary to support all the
// currently supported platforms. One could get by with just None, Reserved, and
// Ready. However, the Prepared state gives us flexibility for performance
// purposes. For example, on POSIX-y operating systems, Reserved is usually a
// private anonymous mmap'd region with PROT_NONE set, and to transition
// to Ready would require setting PROT_READ|PROT_WRITE. However the
// underspecification of Prepared lets us use just MADV_FREE to transition from
// Ready to Prepared. Thus with the Prepared state we can set the permission
// bits just once early on, we can efficiently tell the OS that it's free to
// take pages away from us when we don't strictly need them.
//
// For each OS there is a common set of helpers defined that transition
// memory regions between these states. The helpers are as follows:
//
// sysAlloc transitions an OS-chosen region of memory from None to Ready.
// More specifically, it obtains a large chunk of zeroed memory from the
// operating system, typically on the order of a hundred kilobytes
// or a megabyte. This memory is always immediately available for use.
//
// sysFree transitions a memory region from any state to None. Therefore, it
// returns memory unconditionally. It is used if an out-of-memory error has been
// detected midway through an allocation or to carve out an aligned section of
// the address space. It is okay if sysFree is a no-op only if sysReserve always
// returns a memory region aligned to the heap allocator's alignment
// restrictions.
//
// sysReserve transitions a memory region from None to Reserved. It reserves
// address space in such a way that it would cause a fatal fault upon access
// (either via permissions or not committing the memory). Such a reservation is
// thus never backed by physical memory.
// If the pointer passed to it is non-nil, the caller wants the
// reservation there, but sysReserve can still choose another
// location if that one is unavailable.
// NOTE: sysReserve returns OS-aligned memory, but the heap allocator
// may use larger alignment, so the caller must be careful to realign the
// memory obtained by sysReserve.
//
// sysMap transitions a memory region from Reserved to Prepared. It ensures the
// memory region can be efficiently transitioned to Ready.
//
// sysUsed transitions a memory region from Prepared to Ready. It notifies the
// operating system that the memory region is needed and ensures that the region
// may be safely accessed. This is typically a no-op on systems that don't have
// an explicit commit step and hard over-commit limits, but is critical on
// Windows, for example.
//
// sysUnused transitions a memory region from Ready to Prepared. It notifies the
// operating system that the physical pages backing this memory region are no
// longer needed and can be reused for other purposes. The contents of a
// sysUnused memory region are considered forfeit and the region must not be
// accessed again until sysUsed is called.
//
// sysFault transitions a memory region from Ready or Prepared to Reserved. It
// marks a region such that it will always fault if accessed. Used only for
// debugging the runtime.

```
```asm
munmap()
       The munmap() system call deletes the mappings for the specified address range, and causes further references to addresses within the range to generate invalid memory references.  The region is also  automatically
       unmapped when the process is terminated.  On the other hand, closing the file descriptor does not unmap the region.

       The address addr must be a multiple of the page size (but length need not be).  All pages containing a part of the indicated range are unmapped, and subsequent references to these pages will generate SIGSEGV.  It
       is not an error if the indicated range does not contain any mapped pages.
```

madvise 接受一个地址 一个长度 一个代表建议的常量. 比如告诉 os 这段内存我不用了可以回收了.

sysReserve() 先把地圈起来, port none 表示不让人访问.
## 垃圾回收算法
- mark sweep 标记清除
  - 不会移动对象的位置,c 和 c 艹 之类的提供指针语义的可以用.
- mark compact 标记整理
  - 涉及到对象的移动, 不适合 c & c 艹.
- copy GC
  - 把堆内存分为了 from to 两部分.
- 引用计数法
  - 增加了mutator 的压力.

## 评价垃圾回收算法的好坏的标准
- stw 时间长短
- 吞吐量
- 堆使用效率
- 访问的局部性