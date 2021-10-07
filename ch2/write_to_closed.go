package main
func main() {
    ch := make(chan int)
    close(ch)
    ch <- 1
}
