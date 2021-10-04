package main

import (
	"fmt"
)

type Iface interface {
	Blah() string
}

type A struct {
	a int
}

func (A) Blah() string {
	return "blah"
}

func main() {
	var iface Iface = A{a: 1}
	s := iface.Blah()    // line 21
	fmt.Printf("%s\n", s)
}
