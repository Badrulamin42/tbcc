import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

class SerialPortManager {
    var inputStream: FileInputStream? = null
    var outputStream: FileOutputStream? = null
    var isReading = false
    var listener: ((String) -> Unit)? = null

    fun openSerialPort() {
        try {
            val device = File("/dev/ttyS4")
            if (!device.canRead() || !device.canWrite()) {
                Runtime.getRuntime().exec("chmod 666 /dev/ttyS4")
            }
            inputStream = FileInputStream(device)
            outputStream = FileOutputStream(device)

            isReading = true
            Thread {
                val buffer = ByteArray(1024)
                while (isReading) {
                    val len = inputStream?.read(buffer) ?: -1
                    if (len > 0) {
                        val data = String(buffer, 0, len)
                        listener?.invoke(data)
                    }
                }
            }.start()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun writeData(data: String) {
        outputStream?.write(data.toByteArray())
    }

    fun close() {
        isReading = false
        inputStream?.close()
        outputStream?.close()
    }
}
