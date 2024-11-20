
local enum UdpOptionName
    "dontroute"
    "broadcast"
    "reuseaddr"
    "reuseport"
    "ip-multicast-if"
    "ip-multicast-ttl"
    "ip-multicast-loop"
    "ip-add-membership"
    "ip-drop-membership"
    "ipv6-unicast-hops"
    "ipv6-multicast-hops"
    "ipv6-multicast-loop"
    "ipv6-add-membership"
    "ipv6-drop-membership"
    "ipv6-v6only"
	"recv-buffer-size"
	"send-buffer-size"
end

--- Option table for ip-add-membership | ip-drop-membership
local record UdpMulticastMembership
    multiaddr: string
    inteface: string
end

local type UdpOptionValue = boolean | integer | string | UdpMulticastMembership

local record udp
    metamethod __call: function(any): UdpSocket
    record UdpSocket
        close: function(UdpSocket):integer|nil,string
        getpeername: function(UdpSocket):string,integer
        getsockname: function(UdpSocket):string|nil,integer|string
        receive: function(UdpSocket, size:integer|nil):string|nil,string|nil
        receivefrom: function(UdpSocket, size:integer|nil):string|nil,string,integer|nil
        send: function(UdpSocket,datagram:string):integer|nil,nil|string
        sendto: function(UdpSocket,datagram:string,ip:string,port:integer):integer|nil,nil|string
        setpeername: function(UdpSocket,address:string,port:integer|nil):integer|nil,nil|string
        setsockname: function(UdpSocket,address:string,port:integer):integer|nil, nil|string
        setoption: function(UdpSocket,option_name:UdpOptionName,value:UdpOptionValue):integer|nil,nil|string
        settimeout: function(UdpSocket, timeout:integer|nil)
    end
end


local enum TcpReceivePattern
    "*l"
    "*a"
end

local enum TcpSocketOptionName
    "keepalive"
    "reuseaddr"
    "reuseport"
    "tcp-nodelay"
    "tcp-keepidle"
    "tcp-keepcnt"
    "tcp-keepintvl"
    "ipv6-v6only"
    "linger"
	"recv-buffer-size"
	"send-buffer-size"
    "tcp-defer-accept"
    "tcp-fastopen"
    "tcp-fastopen-connect"
end

local record TcpSocketOptionTable
    on: boolean
    timeout: integer
end

local type TcpSocketOptionValue = boolean | integer | string | TcpSocketOptionTable

local enum TimeoutMode
    "t"
    "b"
end

local enum ShutdownMode
    "both"
    "send"
    "receive"
end
local record tcp
    metamethod __call: function(any): TcpSocket
    record TcpSocket
        accept: function(TcpSocket):TcpSocket|nil,nil|string
        bind: function(TcpSocket, address: string, port: integer): integer|nil, nil|string
        close: function(TcpSocket): integer|nil, nil|string
        connect: function(TcpSocket, address: string, port: integer): TcpSocket|nil, nil|string
        getpeername: function(TcpSocket): string|nil, integer|string
        getsockname: function(TcpSocket): string|nil, integer|string
        getstats: function(TcpSocket): number, number, number
        listen: function(TcpSocket, backlog:integer): integer|nil, nil|string
        receive: function(TcpSocket, pattern: TcpReceivePattern|nil, prefix: string|nil): string|nil, nil|string, nil|string
        send: function(TcpSocket, data: string, integer|nil, integer|nil): integer|nil, nil|string
        setoption: function(TcpSocket, name: TcpSocketOptionName, TcpSocketOptionValue)
        setstats: function(TcpSocket, received: number, sent: number, age: number): integer|nil, nil|string
        settimeout: function(TcpSocket, value: number | nil, mode: TimeoutMode | nil): number|nil, nil|string
        shutdown: function(TcpSocket, mode: ShutdownMode|nil): number|nil, nil|string
    end
end
local record SslInfo
    oid: string
    name: string
    value: string
end

local type SslExtensionList = {string: SslExtension}

local record SslExtension
    name: string
    dNSName: {string}
end

local record SslCertificate
    subject: function(SslCertificate): {SslInfo}
    digest: function(SslCertificate): string|nil, nil|string
    setencode: function(SslCertificate, encode: string): boolean
    extensions: function(SslCertificate): SslExtensionList
    getsignaturename: function(SslCertificate): string
    issuer: function(SslCertificate): {SslInfo}
    notbefore: function(SslCertificate): string
    notafter: function(SslCertificate): string
    issued: function(SslCertificate): string
    pem: function(SslCertificate): string
    pubkey: function(SslCertificate): string
    serial: function(SslCertificate): string
    validat: function(SslCertificate): boolean
end

local record SslSocket
    class: function(SslSocket):string
    close: function(SslSocket): integer|nil, nil|string
    config: function(SslSocket)
    dirty: function(SslSocket): boolean
    dohandshake: function(SslSocket): boolean, nil|string
    getalpn: function(SslSocket): string|{string}|nil, nil|string
    getfinished: function(SslSocket):string
    getpeercertificate: function(SslSocket):SslCertificate
    getpeerchain: function(SslSocket): {SslCertificate}
    getpeerverification: function(SslSocket)
    getpeerfinished: function(SslSocket):string
    getsniname: function(SslSocket):string|nil
    getstats: function(SslSocket):number, number, number
    loadcertificate: function(SslSocket)
    receive: function(SslSocket)
    send: function(SslSocket)
    setdane: function(SslSocket):boolean
    setstats: function(SslSocket):boolean
    settlsa: function(SslSocket):boolean
    sni: function(SslSocket):string
    want: function(SslSocket):string
    settimeout: function(SslSocket, timeout: number): integer|nil,nil|string
end

local enum SslSocketMode
    "client"
    "server"
end

local record SslConfig
    mode: SslSocketMode
    protocol: string|nil
    key: string|nil
    certificate:string|nil
    cafile: string|nil
    verify: {string}
    options: string|{string}
end

local record ssl
    wrap: function(tcp.TcpSocket, config: SslConfig): SslSocket|nil, nil|string
    newcontext: function(SslSocket, config: SslConfig): SslConfig
end

local record socket
    udp: udp
    tcp: tcp   
    ssl: ssl
    select: function({any}|nil, {any}| nil, number|nil): {any}|nil, {any}|nil, nil|string
    sleep: function(timeout: number)
end

local record channel
    record Link<T>
        queue: {T}
        closed: boolean
        waker: function()
    end
    record SendHalf<T>
        link: Link<T>
        settimeout: function(SendHalf<T>, timeout: number)
        close: function(SendHalf<T>)
        send: function(SendHalf<T>, T)
    end
    record ReceiveHalf<T>
        link: Link<T>
        settimeout: function(ReceiveHalf<T>, timeout: number)
        close: function(ReceiveHalf<T>)
        setwaker: function(string, function())
        receive: function(ReceiveHalf<T>): T|nil, nil|string
    end
    new: function<T>():SendHalf<T>, ReceiveHalf<T>
end

local record cosock
    socket: socket
    channel: channel
    ssl: ssl
    spawn: function(function(), string|nil)
    run: function()
    asyncify: function<T>(string):T
end

return cosock
