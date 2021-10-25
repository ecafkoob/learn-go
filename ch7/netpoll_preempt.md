先理一下 socket 监听端口的流程.
1. socket 创建一个 socket fd [socket(2)](https://man7.org/linux/man-pages/man2/socket.2.html) param: domain type protocol 
2. bind 给这个 fd 设置名字. [bind(2)](https://www.man7.org/linux/man-pages/man2/bind.2.html) param: sockfd, sockaddr, addrlen 
3. listen 把 sockfd 设置为活动的 socket, 他可以使用 accept 允许连接. [listen(2)](https://man7.org/linux/man-pages/man2/listen.2.html) param: sockfd, backlog
4. accept accept a connection on a socket [accept(2)](https://man7.org/linux/man-pages/man2/accept.2.html)
5. epoll_create  open an epoll file descriptor. 底层对应一颗红黑树. [epoll_create ](https://man7.org/linux/man-pages/man2/epoll_create.2.html)
6. epoll_wait wait for an I/O event on an epoll file descriptor [epoll_wait](https://man7.org/linux/man-pages/man2/epoll_wait.2.html)
7. epoll_ctl control interface for an epoll file descriptor. [epoll_ctl](https://man7.org/linux/man-pages/man2/epoll_ctl.2.html)
8. read read from a file descriptor [read](https://man7.org/linux/man-pages/man2/read.2.html)
9. write write to a file descriptor [write](https://man7.org/linux/man-pages/man2/write.2.html)

关于 fd, 这个 Unix 最最重要的抽象. Unix 系统一切皆文件. 那么 go 语言一定会使用系统提供的 syscall. 那么就
需要对底层fd进行封装. 

go 对 fd 包装的方式:

- net/netFD  os/File 他们就是对 poll.FD 的封装并且添加了相应的功能. 

- poll.FD 

- sysfd 对应系统的的 fd.


首先golang 对不同平台的 poll在 runtime 进行了统一的抽象.在 fd_poll_runtime.go 里面定义.

看一下 netpoll 的启动流程:

pollDesc 的 init 方法会调用 runtime_pollServerInit() 调用 netpollGenericInit()
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

epoll_wait:

