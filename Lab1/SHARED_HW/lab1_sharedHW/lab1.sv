module lab1 #
(
	parameter WIDTHIN = 16,		// Input format is Q2.14 (2 integer bits + 14 fractional bits = 16 bits)
	parameter WIDTHOUT = 32,	// Intermediate/Output format is Q7.25 (7 integer bits + 25 fractional bits = 32 bits)
	// Taylor coefficients for the first five terms in Q2.14 format
	parameter [WIDTHIN-1:0] A0 = 16'b01_00000000000000, // a0 = 1
	parameter [WIDTHIN-1:0] A1 = 16'b01_00000000000000, // a1 = 1
	parameter [WIDTHIN-1:0] A2 = 16'b00_10000000000000, // a2 = 1/2
	parameter [WIDTHIN-1:0] A3 = 16'b00_00101010101010, // a3 = 1/6
	parameter [WIDTHIN-1:0] A4 = 16'b00_00001010101010, // a4 = 1/24
	parameter [WIDTHIN-1:0] A5 = 16'b00_00000010001000  // a5 = 1/120
)
(
	input clk,
	input reset,	
	
	input i_valid,
	input i_ready,
	output o_valid,
	output o_ready,
	
	input [WIDTHIN-1:0] i_x,
	output [WIDTHOUT-1:0] o_y
);
//Output value could overflow (32-bit output, and 16-bit inputs multiplied
//together repeatedly).  Don't worry about that -- assume that only the bottom
//32 bits are of interest, and keep them.
logic [WIDTHIN-1:0] x;	// Register to hold input X
logic [WIDTHOUT-1:0] y_Q;	// Register to hold output Y
logic valid_Q1;		// Output of register x is valid
logic valid_Q2;		// Output of register y is valid
logic output_give;      //Used to determine if we need a new i_x

//Stages defined
logic [2:0] Stage = 3'b000;

// signal for enabling sequential circuit elements
logic enable;

//register to control all the input at each point
logic [2:0] control=3'b000;

// Signals for computing the y output
logic [WIDTHOUT-1:0] m0_out;
logic [WIDTHOUT-1:0] a0_out;
logic [WIDTHOUT-1:0] m1_out;
logic [WIDTHOUT-1:0] y_D;

//Registers to select what input goes in
logic [WIDTHOUT-1:0] m0_in;
logic [WIDTHOUT-1:0] m1_in;
logic [WIDTHOUT-1:0] a0_in;
logic [WIDTHOUT-1:0] a1_in;

//Registes to hold the values that go into m0,m1,a0,a1
logic [WIDTHOUT-1:0] m1_hold;
logic [WIDTHOUT-1:0] m2_hold;
logic [WIDTHOUT-1:0] a1_hold;
logic [WIDTHOUT-1:0] a2_hold;


// compute y value
//We decide which output we need based on the input size
mult32x16 Mult0 (.i_dataa(m0_in), .i_datab(m1_in), .o_res1(m0_out), .o_res2(m1_out));
addr32p16 Addr0 (.i_dataa(a0_in), 	.i_datab(a1_in), 	.o_res(a0_out));

// Combinational logic
always_comb begin
	// signal for enable
	enable = i_ready;
	m0_in = m1_hold;		//These are registers that take the values of hold registers
	m1_in = m2_hold;		//irrespective of clock
	a0_in = a1_hold;
	a1_in = a2_hold;
end
always_ff @(posedge clk or posedge reset) begin
	if (reset) begin
		valid_Q1 <= 1'b0;
		valid_Q2 <= 1'b0;
		output_give <= 1'b0;
		x <= 0;
		y_Q <= 0;
		Stage = 3'b000;
	end
	else if (enable) begin
		if (Stage == 3'b000) begin //Initial State
			output_give <= 1; 		// This register provides information to o_ready that we are ready to accept new i_x
			valid_Q2 <= 0;				// This register provides information to o_valid that we do not have a output ready
			Stage <= 3'b011;			// Move to Decider state
		end
		else if (Stage == 3'b001)begin //First Multiplication state
			output_give <= 0;
			valid_Q2 <= 0;
			m2_hold <= x;				//first time we provide X along with A5
			m1_hold <= A5;
			Stage <= 3'b010;			//Move to Addition State
		end
		else if (Stage == 3'b010)begin //Addition State
			output_give <= 0;				//We use a control that decides what input needs to go when
			valid_Q2 <= 0;					//similar to a MUX
			if(control == 3'b000) begin //Adder 1
				a1_hold <= m0_out;		//First mutiplier output and A4 value
				a2_hold <= A4;				
				control = 3'b001;			//Move to Adder 2
				Stage = 3'b101;			//Move to next mutiplication 
			end
			else if(control == 3'b001) begin//Adder 2
				a1_hold <= m1_out;		//Mutiplication with 2nd mutiplication output and A3 value
				a2_hold <= A3;	
				control <= 3'b010;		//Move to Adder 3
				Stage <= 3'b101;			//Move to next mutiplication
			end
			else if(control == 3'b010) begin//Adder 3
				a1_hold <= m1_out;		//Mutiplication with 2nd mutiplication output and A2 value
				a2_hold <= A2;
				control <= 3'b011;		//Move to Adder 4
				Stage <=  3'b101;			//Move to next mutiplication
			end
			else if(control == 3'b011) begin//Adder 4
				a1_hold <= m1_out;		//Mutiplication with 2nd mutiplication output and A1 value
				a2_hold <= A1;
				control <= 3'b100;		//Move to Final adder
				Stage <=  3'b101;			//Move to next mutiplication
			end
			else if(control == 3'b100) begin//Final Adder
				a1_hold <= m1_out;		//Mutiplication with 2nd mutiplication output and A0 value
				a2_hold <= A0;
				control <= 3'b000;		//Move to Adder 1
				Stage <= 3'b111;			//Move to Final State
			end
		end
		else if (Stage == 3'b101)begin //Consecutive Mutiplication state
			output_give <= 0;
			valid_Q2 <= 0;
			m2_hold <= x;
			m1_hold <= a0_out;			//Based on the previous Adders output from Addition state 
			Stage <= 3'b010;				//we calculate input for next Adder
		end
		else if (Stage == 3'b011)begin //Decider State to see if we get valid input or not based on output_give register
			output_give <= 0;				// the output_give provides info to o_ready to send x
			valid_Q2 <= 0;
			if (i_valid) begin // Based on i_valid we decide if we compute output
				x <= i_x;			// Store X values for future use
				Stage <= 3'b001;	//Moves to first mutiplication state.
			end
			else begin
				Stage <= 3'b000; //Moves to initial state 
			end
		end
		else if (Stage == 3'b111) begin // Final state where we store our final output
			y_Q <= a0_out;					//We used y_Q to store it and later on push it to o_y
			output_give <= 1;				// This register provides information to o_ready that we are ready to accept new i_x
			valid_Q2 <= 1;					// This register provides information to o_valid that we have a output ready
			Stage <= 3'b011;				//Moves to Decider State
		end
	end
end
// assign outputs
assign o_y = y_Q;
// ready for inputs as long as receiver is ready for outputs */
assign o_ready = output_give;  		
// the output is valid as long as the corresponding input was valid and 
//	the receiver is ready. If the receiver isn't ready, the computed output
//	will still remain on the register outputs and the circuit will resume
//  normal operation when the receiver is ready again (i_ready is high)
assign o_valid = valid_Q2;	

endmodule

/*******************************************************************************************/
/*
// Multiplier module for the first 16x16 multiplication
module mult16x16 (
	input  [15:0] i_dataa,
	input  [15:0] i_datab,
	output [31:0] o_res
);

logic [31:0] result;

always_comb begin
	result = i_dataa * i_datab;
end

// The result of Q2.14 x Q2.14 is in the Q4.28 format. Therefore we need to change it
// to the Q7.25 format specified in the assignment by shifting right and padding with zeros.
assign o_res = {3'b000, result[31:3]};

endmodule
*/
/*******************************************************************************************/

// Multiplier module for all the remaining 32x16 multiplications
module mult32x16 (
	input  [31:0] i_dataa,
	input  [15:0] i_datab,
	output [31:0] o_res1,
	output [31:0] o_res2
);

logic [47:0] result;

always_comb begin
	result = i_dataa * i_datab;
end
// The result of Q2.14 x Q2.14 is in the Q4.28 format. Therefore we need to change it
// to the Q7.25 format specified in the assignment by shifting right and padding with zeros.
assign o_res1 = {3'b000, result[31:3]};// For 16*16 bit multiplier

// The result of Q7.25 x Q2.14 is in the Q9.39 format. Therefore we need to change it
// to the Q7.25 format specified in the assignment by selecting the appropriate bits
// (i.e. dropping the most-significant 2 bits and least-significant 14 bits).
assign o_res2 = result[45:14];// For 32*16 bit multiplier

endmodule

/*******************************************************************************************/

// Adder module for all the 32b+16b addition operations 
module addr32p16 (
	input [31:0] i_dataa,
	input [15:0] i_datab,
	output [31:0] o_res
);

// The 16-bit Q2.14 input needs to be aligned with the 32-bit Q7.25 input by zero padding
assign o_res = i_dataa + {5'b00000, i_datab, 11'b00000000000};

endmodule

/*******************************************************************************************/