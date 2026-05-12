## **Final Project: Real-Time Video Capture and Processing System**

**Group Size:** 3–4 Students

**Hardware Provided:** Basys 3 FPGA Board, OV7670 Camera Module, VGA Cable/Monitor

### **1\. Project Overview**

The goal of this final project is to design and implement a real-time video processing pipeline on an FPGA. You will interface the OV7670 camera module with the Basys 3 board, store the incoming pixel data in a frame buffer, and output the video stream to a monitor using the VGA standard.

This project will test your ability to integrate multiple digital systems, manage clock domains, utilize Block RAM (BRAM), and implement hardware-level image processing algorithms.

### **2\. Specifications & Requirements**

To successfully complete the baseline of this project, your system must meet the following criteria:

* **Camera Interface:** Configure the OV7670 camera via the SCCB (I2C-like) protocol and correctly capture the incoming parallel pixel data and synchronization signals (PCLK, VSYNC, HREF).  
* **Memory Management (Frame Buffer):** Store the captured image data in the Basys 3's internal Block RAM.  
* **VGA Output:** Generate the correct horizontal and vertical sync signals (HSYNC, VSYNC) to drive a VGA monitor.  
* **Base Resolution:** The displayed video stream must have a resolution of **320x200 or 320x240 pixels**. *(Note: You will need to configure the camera for a specific resolution/sub-sampling or handle downsampling in your Verilog design).*

### **3\. Image Processing Filters (Requirement for Full Score)**

To achieve a full score on the functional portion of this project, you must implement **three different hardware-based image filters**. These filters must be applied to the video stream in real-time.

You may choose any three distinct filters. Examples include, but are not limited to:

* Grayscale conversion  
* Color inversion (Negative)  
* Thresholding (Binary image)  
* Color channel isolation (e.g., Red-only, Green-only, Blue-only)  
* Basic edge detection or convolution (Advanced)

*Your design should include a way to switch between the raw video feed and the three different filters (e.g., using the slide switches on the Basys 3).*

### **4\. Extra Credit:** 

### 	**You may implement some of these functionality to get an extra credit.**

1. ### **Full VGA Resolution (640x480)**

Students who successfully output a continuous video stream at a full **640x480 resolution** will receive extra credit. It must be real 640x480, i.e. not 320x240 and repeatedly upsampled in blocks of 2x2. 

**Engineering Challenge:** The Basys 3 board has 1,800 Kbits of BRAM. A standard 640x480 image at 12-bit color requires over 3.6 Mbits of memory. To achieve this extra credit, you will need to creatively manage your memory architecture (e.g., reducing color depth, using a line buffer instead of a full frame buffer, or implementing real-time processing without full storage).

2. ### **Simple NN for detection/classification**

   Even with a small FPGA, you can still run NN by compiling NN to the actual hardware. For example,   
- [https://xilinx.github.io/finn/](https://xilinx.github.io/finn/)  
- [https://www.latticesemi.com/en/Products/DesignSoftwareAndIP/AIML/NeuralNetworkCompiler](https://www.latticesemi.com/en/Products/DesignSoftwareAndIP/AIML/NeuralNetworkCompiler)   
- [https://github.com/pytorch/glow](https://github.com/pytorch/glow)

	Detection or classification can be something simple, but not trivial, simple hand, face detection, box, barcode, are OK.  Detecting if the picture has more green or blue is not

3. ### **Non-trivial Video Upscalling**

   If you do 1280x960 resolution with non-trivial upscaling such as:  
- Bilinear filter  
- Bicubic filter

The nearest neighbor is too trivial.

4. If you have other ideas for extra credits, you can talk to the instructors and get approved before demonstration.

### **5\. Technical Note: VGA Resolution Standard**

There is no standard 320x200 or 320x240.  To display a lower resolution on a modern monitor, you will still generate the standard **640x480 @ 60Hz** sync signals (Hsync and Vsync). You achieve the "lower" resolution through **pixel doubling** (scaling):

1. **Horizontal Doubling:** Hold the same pixel data from memory for *two* consecutive pixel clock cycles.  
2. **Vertical Doubling:** Read the same row of pixels from memory for *two* consecutive horizontal lines.

Again, in order to get the extra credit, you must display an image with a real 640x480 number of pixels.

Hint: You should try to get a display working first on Basys3.  

### **Project Deliverables & Timeline**

**Phase 1: Initial Progress (Due: One week after final project announcement)**

* **Requirement:** Finalize your group of 3–4 members. Submit a brief document listing your team members and a short summary of the three image filters you intend to implement.

**Phase 2: Project Demonstration & Final Submission (Due: Finals Week)**

* **Live Demonstration:** You must demonstrate your working hardware to the instructor. This presentation **must include a proper system block diagram** detailing your data path, clock domains, and memory usage. You will be expected to toggle through your base resolution and the three implemented filters.  
* **Final Submission:** Concurrently with your demo, submit your well-commented source code (Verilog/SystemVerilog and .xdc constraints) and a final project report.  
* **AI Usage Declaration:** If artificial intelligence (e.g., ChatGPT, Gemini, Copilot) was used to generate code, troubleshoot bugs, or draft the report, it must be explicitly declared in your final submission.

---

### **Grading Rubric (30 Points Total)**

| Grading Category | Specific Criteria | Points |
| :---- | :---- | :---- |
| **Phase 1: Initial Progress** | Group of 3–4 students formed and submitted by the one-week deadline. | **5** |
| **Simulation & Testbenches** | Comprehensive testbenches provided for each major module (e.g., VGA sync controller, SCCB camera interface, memory addressing, and filters). Simulation waveforms must demonstrate correct logical behavior prior to synthesis. | **5** |
| **Hardware Interfacing & Base Resolution** | OV7670 camera properly configured via SCCB. Video successfully captured, stored, and displayed via VGA at the baseline **320x200 or 320x240** resolution. | **10** |
| **Hardware Image Filters** | Three distinct image processing filters successfully implemented and togglable in real-time (10 points per functioning filter). | **10** |
| **Project Demonstration** | Clear presentation of a proper system block diagram. Hardware performs as expected during the live demo. Students can effectively answer technical questions about their design. | **5** |
| **Code Quality & Final Report** | Source code is readable, modular, and well-commented. The report clearly explains the design architecture, state machines, and any challenges faced. | **5** |
| **AI Usage Disclosure** | *Pass/Fail Requirement.* If AI tools were used, their specific application (e.g., "Used Copilot for VGA timing generation") must be clearly stated in the report. Failure to disclose AI usage where it is evident may result in a severe penalty. | **—** |
| **EXTRA CREDIT** | Extra credit score is up to the evaluator.  | **\+5** |

| FPGA Pin | Camera Pin |
| :---- | :---- |
| P17 | D0 |
| N17 | D1 |
| M19 | D2 |
| M18 | D3 |
| L17 | D4 |
| K17 | D5 |
| C16 | D6 |
| B16 | D7 |
| A17 | HRE |
| A16 | PCLK |
| R18 | PWDN |
| P18 | RST |
| A14 | SCL |
| A15 | SDA |
| B15 | VSY |
| C15 | XCLK |

