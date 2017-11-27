rbxmk.delete{rbxmk.output{"Proxy.rbxlx"}}
rbxmk.map{
	rbxmk.input{"base.rbxlx"},
	rbxmk.output{"Proxy.rbxlx"},
}
rbxmk.map{
	rbxmk.input{"main.script.lua"},
	rbxmk.output{"Proxy.rbxlx", "ServerScriptService"},
}
rbxmk.map{
	rbxmk.input{"Proxy.modulescript.lua"},
	rbxmk.input{"Test.modulescript.lua"},
	rbxmk.output{"Proxy.rbxlx", "ServerScriptService.main"},
}
rbxmk.map{
	rbxmk.input{"ReceiveReports.localscript.lua"},
	rbxmk.output{"Proxy.rbxlx", "ReplicatedFirst"},
}
