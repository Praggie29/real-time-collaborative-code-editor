import express from "express"
import { createServer } from "http"
import { Server } from "socket.io"
import { YSocketIO } from "y-socket.io/dist/server"

const PORT = process.env.PORT || 3000
const CORS_ORIGIN = process.env.CORS_ORIGIN || "*"

const app = express()
app.use(express.static("public"))


const httpServer = createServer(app)

const io = new Server(httpServer, {
    cors: {
        origin: CORS_ORIGIN,
        methods: [ "GET", "POST" ]
    }
})


const ySocketIO = new YSocketIO(io)
ySocketIO.initialize()


app.get('/health', (req, res) => {
    res.status(200).json({
        message: "ok",
        success: true,
        uptime: process.uptime()
    })
})


httpServer.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}`)
})


// Graceful shutdown for container environments (ECS, Docker)
const shutdown = (signal) => {
    console.log(`${signal} received. Shutting down gracefully...`)
    httpServer.close(() => {
        console.log("HTTP server closed")
        process.exit(0)
    })
    // Force exit after 10s if connections don't close
    setTimeout(() => process.exit(1), 10000)
}

process.on("SIGTERM", () => shutdown("SIGTERM"))
process.on("SIGINT", () => shutdown("SIGINT"))