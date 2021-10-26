先理一下 socket 监听端口的流程.
1. socket 创建一个 socket fd [socket(2)](https://man7.org/linux/man-pages/man2/socket.2.html) param: domain type protocol 
2. bind 给这个 fd 设置名字. [bind(2)](https://www.man7.org/linux/man-pages/man2/bind.2.html) param: sockfd, sockaddr, addrlen 
3. listen 把 sockfd 设置为活动的 socket, 他可以使用 accept 允许连接. [listen(2)](https://man7.org/linux/man-pages/man2/listen.2.html) param: sockfd, backlog
4. accept accept a connection on a socket [accept(2)](https://man7.org/linux/man-pages/man2/accept.2.html)
   1. epoll_create  open an epoll file descriptor. 底层对应一颗红黑树. [epoll_create ](https://man7.org/linux/man-pages/man2/epoll_create.2.html)
5. epoll_wait wait for an I/O event on an epoll file descriptor [epoll_wait](https://man7.org/linux/man-pages/man2/epoll_wait.2.html)
这个有三个或者 4 个参数,第一个 epfd, 第二个是一个 bufffer 指向 epollevent buffer,这里应该是 epollevent 的数组.然后后面是个数字, 指的是 event的最大数量. 最后一个
是 一个超时的时间. 应该是 在这个时间就会把 结果返回. 如果调用 epollwait 会阻塞，当有可用的event来了.或者到了超时时间就会执行一次.
6. epoll_ctl control interface for an epoll file descriptor. [epoll_ctl](https://man7.org/linux/man-pages/man2/epoll_ctl.2.html) 这个就是向 epfd 注册事件.提供一个要监听fd
还有一个 pollevent 这样内核就可以在事件就绪的时候向 epollwait 通知事件了. 这里有个有趣的事情. 就是当成参数传进去的 fd 就是内核应该查询的
的 fd. 这个 fd 在 epollevent 的 data 字段中有. 那为啥内核实现不直接从 epollevent 里面拿呢? 这个应该和内核实现有关.
7. read read from a file descriptor [read](https://man7.org/linux/man-pages/man2/read.2.html)
8. write write to a file descriptor [write](https://man7.org/linux/man-pages/man2/write.2.html)

关于 fd, 这个 Unix 最最重要的抽象. Unix 系统一切皆文件. 那么 go 语言一定会使用系统提供的 syscall. 那么就
需要对底层fd进行封装. 

go 对 fd 包装的方式:

- net/netFD  os/File 他们就是对 poll.FD 的封装并且添加了相应的功能. 

- poll.FD 里面有一个 pollDesc 这个就是对 poll 相关操作的抽象. 这玩意有两个定义 一个是 runtime 的.一个是 netpoll 里面的.
fd_poll_runtime.go 这个文件是属于 poll package 的. netpoll.go 是属于 runtime 的. 前者只包含函数签名.后者包含了实现.通过
linkname 打通了包之间不可以直接调用的限制. 真是骚的不行. poll 也没有暴露出 pollDesc 的定义.

- sysfd 对应系统的的 fd.


首先golang 对不同平台的 poll在 runtime 进行了统一的抽象.在 fd_poll_runtime.go 里面定义.

看一下 netpoll 的启动流程:

pollDesc 的 init 方法会调用 runtime_pollServerInit() 调用 netpollGenericInit()这个相当于 epollcreate
netpollGenericInit ->  netpollinit() 

这个 netpollinit 有点意思:
1. 创建 调用 golang 的 epollcreate 函数, 其实就是一个汇编的封装.
2. 创建了一个 非阻塞的管道.这玩意儿也是调用 syscall 实现的.
3. 然后就是 epoll 注册事件之类的事情了.
4. epoll_ctl param: epfd, op, fd , event  epfd 代表 epoll 这个东西. op 有 add mod del , event 表示可读
可写之类的东西.
5. 他把 pipe 的 r w 两端都付给了 全局变量. r 的那端还赋给了 epoll_ctl 


问题 pipe  这玩意怎么玩的? 创建一个 pipe 返了两个 fd 一个读一个写, 把 r 的那个 fd 传给了 epoll_ctl.
此处保留疑问. 

到了这里就建立起了和 系统调用之间的联系.poll 这坨搞清楚了.该看看其他的对应在哪里了. 比如 socket  bind 这些.

### TCP Listen
net.Listen() 通过输入的参数 network 和 addr 两个 string 返回 Listener 接口. 这个设计好啊.现在有 TCPListener
UnixListener 这些结构体. 后面再根据规范添加 xxxListener 即可. 只要他们实现了 Listener 接口即可.

这个 Listen() parse 出 addr 是 TCPaddr 就直接构造一个 sysListener 然后调用 listenTCP 方法. 这个方法里面调用 internetSocket-> 通过 socket 创建 netFD
创建了一个 TCPListener  netFD 有个 listenStream 函数会进行 bind syscall

现在我们有了一个 TCPListener 就可以通过这个来 Accept 了. 
```
type TCPListener struct {
	fd *netFD //这个很关键
	lc ListenConfig
}
```

### TCP Accept
1. TCPListener accept
2. netFD accept
3. poll.FD Accept
4. pollDesc waitRead
5. pollDesc wait

```
func netpollopen(fd uintptr, pd *pollDesc) int32 {
var ev epollevent
ev.events = _EPOLLIN | _EPOLLOUT | _EPOLLRDHUP | _EPOLLET
*(**pollDesc)(unsafe.Pointer(&ev.data)) = pd
return -epollctl(epfd, _EPOLL_CTL_ADD, int32(fd), &ev)
}
```

### TCP Read
1. net.TCPConn 这个结构体里面包含了 conn conn 实现了 Reader 接口. 所以 TCPConn 也就实现了 Reader.
2. net.conn Read conn 里面有个 netFD
3. netFD Read
4. poll.FD Read
5. syscall.Read

如果 read 遇到 EAGAIN 则:
6. pollDesc waitRead
7. pollDesc wait
8. runtime pollWait

### TCP Write
1. net.TCPConn Write
2. net.conn Write
3. netFD Write
4. poll.FD Write
5. syscall.Write

如果 write 遇到 EAGAIN 则:
6. pollDesc waitWrite
7. pollDesc write
8. runtime pollWait

### pollWait 流程
1. netpoll
2. gopark
