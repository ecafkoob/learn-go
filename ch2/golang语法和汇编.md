# golang 的编译过程
- 词法分析 自带的 go/token 包就是干这个的.
- 语法分析 go/parser 通过词条流生成 ast
- 语义分析 在 ast 上进行,比如编译期类型检查
- 中间代码生成 
- 中间代码优化
- 机器码生成

#### 通过 go编译过程我们在工程中能干啥?
- 满足好奇心,和同事吹牛逼.
- 理解语法和汇编结果之间的对应
- 通过 ast 做一些牛逼的事情. 比如写个简单的 parser ,简单的 linter.
- 举一反三,可以看看那些原来感觉很牛逼的 sql parser.原理都是相通的.

#### 知道 go tool 这个命令下都有什么命令.

```shell
addr2line
api
asm
buildid
cgo
compile
cover
dist
doc
fix
link
nm
objdump
pack
pprof
test2json
trace
vet
```
- compile 把源码编译成 .o 文件
- cover 测试覆盖率
- doc 文档相关的功能
- link 链接目标文件生成可执行文件
- nm 查看 文件的符号 .o 和 binary 都行.
- objdump 反汇编 binary 文件
- pprof profile 工具.
- trace:
```shell
trace 的用法:
Supported profile types are:
    - net: network blocking profile
    - sync: synchronization blocking profile
    - syscall: syscall blocking profile
    - sched: scheduler latency profile
```

### 这次主要是用 compile 和 objdump 还有 ssa 生成工具进行实验

1. 记录: 写一个关闭状态的 channel panic 的过程
```go
package main
func main() {
	ch := make(chan int)
	close(ch)
	ch <-1
}
```
通过 go tool compile -S ./write_to_closed.go 得到汇编代码
```asm
        0x0014 00020 (write_to_closed.go:3)     LEAQ    type.chan int(SB), AX
        0x001b 00027 (write_to_closed.go:3)     XORL    BX, BX
        0x001d 00029 (write_to_closed.go:3)     PCDATA  $1, $0
        0x001d 00029 (write_to_closed.go:3)     NOP
        0x0020 00032 (write_to_closed.go:3)     CALL    runtime.makechan(SB)
        0x0025 00037 (write_to_closed.go:3)     MOVQ    AX, "".ch+16(SP)
        0x002a 00042 (write_to_closed.go:4)     PCDATA  $1, $1
        0x002a 00042 (write_to_closed.go:4)     CALL    runtime.closechan(SB)
        0x002f 00047 (write_to_closed.go:5)     MOVQ    "".ch+16(SP), AX
        0x0034 00052 (write_to_closed.go:5)     LEAQ    ""..stmp_0(SB), BX
        0x003b 00059 (write_to_closed.go:5)     PCDATA  $1, $0
        0x003b 00059 (write_to_closed.go:5)     NOP
        0x0040 00064 (write_to_closed.go:5)     CALL    runtime.chansend1(SB)
```
简单看一下对应 runtime 函数的实现:
runtime.makechan: 使用的 src/runtime/chan 中的 makechan() 函数. 其实就是初始化 hchan 这个结构体. 返回 *hchan 指针.
runtime.closechan:
 * 先判断 c *hchan 是否为 nil ,nil 则 panic 
 * 判断 c.closed 是否为零, 为零则 panic
 * c.closed 置零
 * 释放所有readers
 * 释放所有的 writers
runtime.chansend1: 调用 chansend() 别的我们不关心.从下面代码我们可以看到为什么 chansend 的时候 panic 了.
```
	if c.closed != 0 {
		unlock(&c.lock)
		panic(plainError("send on closed channel"))
	}
```
2. 记录: 关闭一个 nil channel panic 的过程
首先整一个 nil channel. 
Q: 怎么整呢? 
A: google 到了: var ch chan int

Q: 为啥 var chan int 出来的是 nil  , 而上面例子里面 make 出来的 不是 nil 呢? 有啥区别?
A: 额... 挠头三连... 其实不用我们看汇编
```go
package main
func main() {
	var ch chan int
	close(ch)
}
```
对应的汇编代码:
```
"".main STEXT size=44 args=0x0 locals=0x10 funcid=0x0
        0x0000 00000 (close_nil.go:2)   TEXT    "".main(SB), ABIInternal, $16-0
        0x0000 00000 (close_nil.go:2)   CMPQ    SP, 16(R14)
        0x0004 00004 (close_nil.go:2)   PCDATA  $0, $-2
        0x0004 00004 (close_nil.go:2)   JLS     37
        0x0006 00006 (close_nil.go:2)   PCDATA  $0, $-1
        0x0006 00006 (close_nil.go:2)   SUBQ    $16, SP
        0x000a 00010 (close_nil.go:2)   MOVQ    BP, 8(SP)
        0x000f 00015 (close_nil.go:2)   LEAQ    8(SP), BP
        0x0014 00020 (close_nil.go:2)   FUNCDATA        $0, gclocals·33cdeccccebe80329f1fdbee7f5874cb(SB)
        0x0014 00020 (close_nil.go:2)   FUNCDATA        $1, gclocals·33cdeccccebe80329f1fdbee7f5874cb(SB)
        0x0014 00020 (close_nil.go:4)   XORL    AX, AX
        0x0016 00022 (close_nil.go:4)   PCDATA  $1, $0
        0x0016 00022 (close_nil.go:4)   CALL    runtime.closechan(SB)
        0x001b 00027 (close_nil.go:5)   MOVQ    8(SP), BP
        0x0020 00032 (close_nil.go:5)   ADDQ    $16, SP
        0x0024 00036 (close_nil.go:5)   RET
        0x0025 00037 (close_nil.go:5)   NOP
        0x0025 00037 (close_nil.go:2)   PCDATA  $1, $-1
        0x0025 00037 (close_nil.go:2)   PCDATA  $0, $-2
        0x0025 00037 (close_nil.go:2)   CALL    runtime.morestack_noctxt(SB)
        0x002a 00042 (close_nil.go:2)   PCDATA  $0, $-1
        0x002a 00042 (close_nil.go:2)   JMP     0
```
## 支线任务
发现一个问题.卧槽竟然没有调用 makechan 的过程... 甚至连那一行都被无视了. 
感觉是被编译器优化了,怎么证明呢? 上 ssa
使用 https://golang.design/gossa 挺方便
https://golang.design/gossa?id=5d7d62cb-26fc-11ec-b7a0-0242c0a8d002
选定 var ch chan int 那一行代码, 可以看到对应工序中的代码都被高亮 方便我们查看变化. 虽然看不懂但是可以看到大概的变化过程.
可以得到:
```
v7 (+4) = MOVQstoreconst <mem> {ch} [val=0,off=0] v2 v5 最后编程汇编代码.
genssa 中可知: v7  00003 (+4) MOVQ $0, "".ch-8(SP)
```
看起来编译器一顿操作 var ch chan int 变成了一条 movq 指令,
证实: 
```
➜ go tool objdump -S  -s main.main close_nil
TEXT main.main(SB) /tmp/test/close_nil.go
func main() {
  0x1058dc0             493b6610                CMPQ 0x10(R14), SP
  0x1058dc4             7649                    JBE 0x1058e0f
  0x1058dc6             4883ec20                SUBQ $0x20, SP
  0x1058dca             48896c2418              MOVQ BP, 0x18(SP)
  0x1058dcf             488d6c2418              LEAQ 0x18(SP), BP
    var ch chan int
  0x1058dd4             48c744241000000000      MOVQ $0x0, 0x10(SP)  //这就是 genssa 对应的那个 MOVQ
    println(ch==nil)
  0x1058ddd             c644240f01              MOVB $0x1, 0xf(SP)
  0x1058de2             e81964fdff              CALL runtime.printlock(SB)
  0x1058de7             0fb644240f              MOVZX 0xf(SP), AX
  0x1058dec             e8af66fdff              CALL runtime.printbool(SB)
  0x1058df1             e86a66fdff              CALL runtime.printnl(SB)
  0x1058df6             e88564fdff              CALL runtime.printunlock(SB)
    close(ch)
  0x1058dfb             488b442410              MOVQ 0x10(SP), AX
  0x1058e00             e8fbb3faff              CALL runtime.closechan(SB)
}
  0x1058e05             488b6c2418              MOVQ 0x18(SP), BP
  0x1058e0a             4883c420                ADDQ $0x20, SP
  0x1058e0e             c3                      RET
func main() {
  0x1058e0f             e88cd0ffff              CALL runtime.morestack_noctxt.abi0(SB)
  0x1058e14             ebaa                    JMP main.main(SB)
```

做完支线任务回到主线,看看是如何 panic 的
```
(dlv) si
> runtime.closechan() /usr/local/Cellar/go/1.17.1/libexec/src/runtime/chan.go:355 (PC: 0x1004200)
Warning: debugging optimized function
   350:         src := sg.elem
   351:         typeBitsBulkBarrier(t, uintptr(dst), uintptr(src), t.size)
   352:         memmove(dst, src, t.size)
   353: }
   354:
=> 355: func closechan(c *hchan) {
   356:         if c == nil {
   357:                 panic(plainError("close of nil channel"))
   358:         }
   359:
   360:         lock(&c.lock)
```
```
(dlv) n
> runtime.closechan() /usr/local/Cellar/go/1.17.1/libexec/src/runtime/chan.go:356 (PC: 0x1004220)
Warning: debugging optimized function
   351:         typeBitsBulkBarrier(t, uintptr(dst), uintptr(src), t.size)
   352:         memmove(dst, src, t.size)
   353: }
   354:
   355: func closechan(c *hchan) {
=> 356:         if c == nil {
   357:                 panic(plainError("close of nil channel"))
   358:         }
   359:
   360:         lock(&c.lock)
   361:         if c.closed != 0 {
(dlv) p c
*runtime.hchan nil
```
到这里基本就很清楚了. c == nil 进入 panic 流程 最后打印 error msg 调用 exit(2) 退出.

4. 记录: 关闭一个已经关闭 channel panic 的过程
由上面知识可知:
close(ch) 把  c *hchan 的 c.closed 字段置为 1  下次 检查 c.closed != 0 直接 panic.


### 修正压缩包中的 ast_map_expr 文件夹中的 test，使 test 可以通过

Eval 接受 map , 和一个符合 go 语法的 表达式字符串. 通过 golang  parser 把 string 转成 ast.Expr 调用 judge 

judge 就收 m 和 之前的 ast.Expr 对ast 进行递归处理. 调用 isLeaf 判断是否为叶子节点. 

isLeaf 接受一个 ast.Node 判断左右子树是否为 Ident 和 BasicLit 如果是那么当前节点就是叶子结点. 否则就是 ast 的根节点.

在 judge 中 如果是叶子节点 需要进行处理.

在处理叶子节点和 map 时需要注意. 虽然 ast 的子树有 name 字段. 但是 map 不一定有这个 key 如果不做处理, map[string]string
会返回 "" 而空string 和 任何 字符串形式的数字相比都是小于.不会报错,但是结果是错误的.

还有一点值得注意 编译器在编译就可以确定两个 字符串形式数字的比较. 而不需要 strconv.Atoi()


添加了 小于 小于等于 大于等于支持

所以修改的代码如下:
```
		if _,ok:= m[x.Name]; !ok {
			panic("error invalid map key!")
		}
		switch expr.Op {
		case token.GTR:
			return m[x.Name] > y.Value
		case token.LSS:
			return m[x.Name] < y.Value
		case token.GEQ:
			return m[x.Name] >= y.Value
		case token.LEQ:
			return m[x.Name] <= y.Value
		}
```



