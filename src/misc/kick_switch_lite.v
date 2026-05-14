// =========================================================================
// kick_switch_lite.v
// Copies Kickstart ROM from Flash to SDRAM
// Detects OSD kickstart selection changes and restarts the copy routine
//
// To use the Kick Switch Lite, the ROMs must be flashed like this:
//
// 0x400000 Kickstart 3.1 / 512k (default)
// 0x700000 Kickstart 1.3 / 256k (optional)
// 0x740000 Kickstart 1.3 / 256k (optional)
// 0x780000 Kickstart 3.2 / 512k (optional)
// =========================================================================

module kick_switch_lite (
    // Clock & reset
    input  wire        clk,
    input  wire        pll_lock,

    // Memory ready signals
    input  wire        sdram_ready,
    input  wire        mem_ready,

    // OSD kickstart selection
    input  wire [1:0]  osd_kickstart,

    // Flash interface
    input  wire [15:0] flash_dout,
    input  wire        flash_busy,
    output reg  [21:0] flash_addr,
    output reg         flash_cs,

    // SDRAM write interface
    output reg  [21:0] flash_ram_addr,
    output reg  [15:0] flash_ram_data,
    output reg         flash_ram_write,

    // Status
    output wire        rom_done
    input wire         start_rom_copy
);

    // ---- start pulse (rising edge of mem_ready) -------------------------
    
    
    reg [17:0]  flash_ram_addr;   
    reg         flash_ram_write;
    reg [5:0]   flash_cnt;  

    // ---- Flash base address (combinational) -----------------------------
    reg [21:0] flash_addr_base;

    always @(*) begin
        case (osd_kickstart)
            2'b00:   flash_addr_base = 22'h380000; // Kickstart 1.3 @ 7.0 MB
            2'b01:   flash_addr_base = 22'h200000; // Kickstart 3.1 @ 4.0 MB
            2'b10:   flash_addr_base = 22'h3C0000; // Kickstart 3.2 @ 7.5 MB
            default: flash_addr_base = 22'h200000;
        endcase
    end

    // ---- Internal signals -----------------------------------------------
    reg [21:0] word_count;
    reg [4:0]  state;
    reg [5:0]  flash_cnt;
    reg [1:0]  osd_kickstartD;
    reg restart_rom_copy;  

    // once the copy counter has run to zero, all rom has been copied
    wire		rom_done = (word_count == 0);
    assign      rom_done = (word_count == 22'd0);

    // ---- Main state machine ---------------------------------------------
    always @(posedge clk) begin
            restart_rom_copy <= 1'b0;

            if (!mem_ready || (osd_kickstart != osd_kickstartD)) begin
                osd_kickstartD <= osd_kickstart;

                flash_addr      <= flash_addr_base;
                flash_ram_addr  <= 18'h0;           // write into 512k sdram segment used for kick rom
                word_count      <= 22'h40001;       // 512k bytes ROM data = 256k words
                state           <= 5'd0;
                flash_ram_write <= 1'b0;
                flash_cs        <= 1'b0;
                flash_cnt       <= 6'd0;

                if (mem_ready)
                    restart_rom_copy <= 1'b1;
                
            end else begin

            // copy ROM from flash to memory
            if ((start_rom_copy || restart_rom_copy || state == 5'd23) && !rom_done) begin
                flash_cs  <= 1'b1;
                flash_cnt <= 6'd45;
            end else begin
                if (flash_cnt != 6'd0) flash_cnt <= flash_cnt - 6'd1;
                if (flash_busy)        flash_cs  <= 1'b0;

                if (flash_cnt == 6'd1) begin
                    state      <= 5'd1;
                    flash_addr <= flash_addr + 22'd1;
                    word_count <= word_count - 22'd1;

                    /* Patch KS 1.2/1.3: bne.b → bra.b, erzwingt Speicher-
                       erkennung bei jedem Reset. Gilt für beide ROM-Positionen:
                       $f80154 (flash 3800aa) und Mirror $fc0154 (flash 3a00aa). */
                    if ((flash_addr == 22'h3800aa || flash_addr == 22'h3a00aa) &&
                         flash_dout == 16'h6678)
                        flash_ram_data <= flash_dout & 16'hf0ff; // bne.b → bra.b
                    else
                        flash_ram_data <= flash_dout;
                end
            end

            // RAM write state machine
            if (state != 5'd0)  state           <= state + 5'd1;
            if (state == 5'd3)  flash_ram_write <= 1'b1;
            if (state == 5'd18) flash_ram_write <= 1'b0;
            if (state == 5'd21) flash_ram_addr  <= flash_ram_addr + 22'd1;
        end
    end

endmodule
