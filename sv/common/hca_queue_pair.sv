//CREATE INFORMATION
//-----------------------------------------------------------------------------------------------
//
//  (C) COPYRIGHT 2021 BY ICT-HPC CORPORATION ALL RIGHTS RESERVED
//  DATE     : 2021-09-01
//  AUTHOR   : mazhenlong@ncic.ac.cn
//  FILENAME : hca_queue_pair.sv
//  FUNCTION : This file supplies the env of verification of HCA.
//
//-----------------------------------------------------------------------------------------------

//CHANGE HISTORY
//-----------------------------------------------------------------------------------------------
//
//  AUTHOR          DATE          VERSION          REASON
//  mazhenlong      2020-09-01    v1.0             create
//  mazhenlong      2021-09-17    v1.1             add RQ support
//
//-----------------------------------------------------------------------------------------------

`ifndef __HCA_QUEUE_PAIR__
`define __HCA_QUEUE_PAIR__

typedef class hca_queue_list;

//----------------------------------------------------------------------------
//
// CLASS: hca_queue_pair
//
//----------------------------------------------------------------------------
class hca_queue_pair extends uvm_object;

    qp_context ctx;
    hca_queue_pair remote_qp;
    hca_memory mem;

    int host_id;
    bit [10:0] proc_id;

    bool is_connect;

    // header: producer pointer, byte
    // tail: consumer pointer, byte
    addr    sq_header;
    addr    sq_tail;
    addr    sq_last_header;

    addr    rq_header;
    addr    rq_tail;
    addr    rq_last_header;

    wqe     sq[$];
    wqe     rq[$];

    `uvm_object_utils_begin(hca_queue_pair)
    `uvm_object_utils_end

    
    //------------------------------------------------------------------------------
    // function name : new
    // function      : constructor
    // invoked       : invoked when instantiates the class
    //------------------------------------------------------------------------------
    function new(string name = "hca_queue_pair");
        super.new(name);
        sq_header = 0;
        sq_tail = 0;
        sq_last_header = 0;
        rq_header = 0;
        rq_tail = 0;
        rq_last_header = 0;
        is_connect = FALSE;
    endfunction: new

    function bit connect(hca_queue_pair qp_b);
        remote_qp = qp_b;
        qp_b.remote_qp = this;
        this.ctx.remote_qpn = qp_b.ctx.local_qpn;
        qp_b.ctx.remote_qpn = this.ctx.local_qpn;
        this.ctx.rnr_nextrecvpsn = qp_b.ctx.next_send_psn;
        qp_b.ctx.rnr_nextrecvpsn = this.ctx.next_send_psn;
        this.is_connect = TRUE;
        qp_b.is_connect = TRUE;
    endfunction: connect

    //------------------------------------------------------------------------------
    // task name     : put_wqe
    // function      : create wqes of one doorbell and deliver them to 
    //                 both memory and q_list. 
    //                 If operation type is RECEIVE, this task puts WQEs to RQ of 
    //                 the remote QP.
    // invoked       : by create_and_write_wqes
    //------------------------------------------------------------------------------
    task put_wqe(
        e_op_type op_que[$],
        mpt local_mpt_que[$],
        mpt remote_mpt_que[$],
        hca_queue_list q_list,
        hca_check_mem_list check_list,
        int sg_num,
        int sg_data_cnt
    );
        addr desc_byte_len;
        e_op_type op_type;
        e_op_type next_op_type;
        mpt local_mpt;
        mpt remote_mpt;
        int queue_size = 512 * 1024;
        wqe_data_seg_unit data_seg_unit;
        mpt local_mpt_que_check[$];
        mpt remote_mpt_que_check[$];
        int host_id;
        int remote_host_id;
        bit [10:0] proc_id;
        bit [10:0] remote_proc_id;
        hca_queue_pair qp;
        int wqe_num;

        qp = this;
        host_id = this.host_id;
        proc_id = this.proc_id;
        remote_host_id = remote_qp.host_id;
        remote_proc_id = remote_qp.proc_id;

        local_mpt_que_check = local_mpt_que;
        remote_mpt_que_check = remote_mpt_que;
        wqe_num = op_que.size();

        // if (wqe_num != op_que.size()) begin
        //     `uvm_fatal("WQE_NUM_ERR", $sformatf("wqe_num != op_que.size! wqe_num = %d, op_que.size = %d.", wqe_num, op_que.size()));
        // end

        next_op_type = op_que.pop_front();
        
        for (int i = 0; i < wqe_num; i++) begin
        // for (int i = 0; i < op_que.size() + 1; i++) begin
            wqe temp_wqe;

            op_type = next_op_type;
            if (op_que.size() != 0) begin // is not the last WQE
                next_op_type = op_que.pop_front();
            end
            else begin
                next_op_type = OP_INIT;
            end
            
            // set WQE length
            desc_byte_len = 0;
            if (op_type == RECV) begin
                desc_byte_len[ctx.rq_entry_sz_log] = 1'b1;
            end
            else begin
                desc_byte_len[ctx.sq_entry_sz_log] = 1'b1;
            end

            // set next seg
            if (i + 1 == wqe_num) begin // is the last wqe
                if (op_type == RECV) begin
                    temp_wqe.next_seg.next_wqe = 0;
                    temp_wqe.next_seg.res_0 = 1;
                    temp_wqe.next_seg.next_opcode = 0;
                    temp_wqe.next_seg.next_ee = 0;
                    temp_wqe.next_seg.next_dbd = 0;
                    temp_wqe.next_seg.next_fence = 0;
                    temp_wqe.next_seg.next_wqe_size = 0;
                    temp_wqe.next_seg.cq = 0;
                    temp_wqe.next_seg.evt = 0;
                    temp_wqe.next_seg.solicit = 0;
                    temp_wqe.next_seg.res_1 = 1;
                    temp_wqe.next_seg.imm_data = 0;
                end
                else begin
                    temp_wqe.next_seg.next_wqe = 0;
                    temp_wqe.next_seg.next_opcode = 0;
                    temp_wqe.next_seg.next_ee = 0;
                    temp_wqe.next_seg.next_dbd = 0;
                    temp_wqe.next_seg.next_fence = 0;
                    temp_wqe.next_seg.next_wqe_size = 0;
                    temp_wqe.next_seg.cq = 0;
                    temp_wqe.next_seg.evt = 0;
                    temp_wqe.next_seg.solicit = 0;
                    temp_wqe.next_seg.imm_data = 0;
                end
            end
            else begin // is not the last wqe
                case (next_op_type)
                    WRITE: begin
                        temp_wqe.next_seg.next_wqe = ((sq_header + desc_byte_len) % queue_size) >> 4;
                        temp_wqe.next_seg.next_opcode = `VERBS_RDMA_WRITE;
                        temp_wqe.next_seg.next_wqe_size = sg_num + 2;
                    end
                    READ: begin
                        temp_wqe.next_seg.next_wqe = ((sq_header + desc_byte_len) % queue_size) >> 4;
                        temp_wqe.next_seg.next_opcode = `VERBS_RDMA_READ;
                        temp_wqe.next_seg.next_wqe_size = sg_num + 2;
                    end
                    SEND: begin
                        temp_wqe.next_seg.next_wqe = ((sq_header + desc_byte_len) % queue_size) >> 4;
                        temp_wqe.next_seg.next_opcode = `VERBS_SEND;
                        temp_wqe.next_seg.next_wqe_size = sg_num + 1;
                    end
                    RECV: begin
                        temp_wqe.next_seg.next_wqe = ((qp.rq_header + desc_byte_len) % queue_size) >> 4;
                        temp_wqe.next_seg.next_wqe_size = sg_num + 2;
                    end
                    default: begin
                        `uvm_fatal("ILLEGAL_OPCODE", $sformatf("illegal op code in wqe! i: %d, op_que.size: %d.", i, op_que.size()));
                    end
                endcase
            end

            // set ud seg
            if (qp.ctx.flags[15:0] == `HGHCA_QP_ST_UD) begin
                temp_wqe.ud_seg.port = 0;
                temp_wqe.ud_seg.smac = 0;
                temp_wqe.ud_seg.dmac = 0;
                temp_wqe.ud_seg.sip = 0;
                temp_wqe.ud_seg.dip = 0;
                temp_wqe.ud_seg.dqpn = remote_qp.ctx.local_qpn;
                temp_wqe.ud_seg.qkey = 0;
            end

            // set data seg
            for (int data_seg_id = 0; data_seg_id < sg_num; data_seg_id++) begin
                local_mpt = local_mpt_que.pop_front();
                data_seg_unit.byte_count = sg_data_cnt;
                data_seg_unit.lkey = local_mpt.key;
                data_seg_unit.addr = local_mpt.start;
                temp_wqe.data_seg.push_back(data_seg_unit);
            end
            
            // set raddr seg
            case (op_type)
                WRITE,
                READ: begin
                    remote_mpt = remote_mpt_que.pop_front();
                    temp_wqe.raddr_seg.raddr = remote_mpt.start;
                    temp_wqe.raddr_seg.rkey = remote_mpt.key;
                end
                SEND,
                RECV: begin
                    // No need to set raddr seg for SEND/RECV
                end
                default: begin
                    `uvm_fatal("OP_TYPE_ERR", $sformatf("Illegal op_type: %h", op_type));
                end
            endcase

            // set zero seg
            if (op_type == RECV) begin
                temp_wqe.zero_seg.zero = 0;
            end

            if (op_type == RECV) begin
                qp.rq.push_back(temp_wqe);
                `uvm_info("NOTICE", $sformatf("WQE pushed into rq_wqe_list! op_type: %h, raddr_seg.raddr: %h", op_type, temp_wqe.raddr_seg.raddr), UVM_LOW);
                write_wqe_to_mem(qp, temp_wqe, op_type, sg_num);
            end
            else begin
                qp.sq.push_back(temp_wqe);
                `uvm_info("NOTICE", $sformatf("WQE pushed into sq_wqe_list! op_type: %h, raddr_seg.raddr: %h", op_type, temp_wqe.raddr_seg.raddr), UVM_LOW);
                write_wqe_to_mem(qp, temp_wqe, op_type, sg_num);
            end

            // send source address, destination address and length to scoreboard, no need for SEND
            if (op_type != SEND) begin
                send_mem_check(host_id, remote_host_id, proc_id, qp.proc_id, temp_wqe, op_type, local_mpt_que_check, remote_mpt_que_check, check_list);
            end

            // send cqe to scoreboard
            send_ref_cqe(q_list);

            // modify qp pointer
            if (op_type == RECV) begin
                qp.rq_header += desc_byte_len;
            end
            else begin
                qp.sq_header += desc_byte_len;
            end
            if ((qp.sq_header - qp.sq_tail) > 2048) begin
                `uvm_fatal("QP_OVERLAY", "SQ header exceeds tail!");
            end
            if ((qp.rq_header - qp.rq_tail) > 2048) begin
                `uvm_fatal("QP_OVERLAY", "RQ header exceeds tail!");
            end
        end
        qp.sq_last_header = qp.sq_header;
        `uvm_info("NOTICE", "put_wqe finished!", UVM_HIGH);
    endtask: put_wqe

    //------------------------------------------------------------------------------
    // task name     : send_ref_cqe
    // function      : send reference CQE to scoreboard
    // invoked       : by put_wqe
    //------------------------------------------------------------------------------
    task send_ref_cqe(hca_queue_list q_list);
    // warning: need to improve
        hca_comp_queue snd_cq;
        hca_comp_queue rcv_cq;
        cqe temp_cqe;
        snd_cq = q_list.cq_list[host_id][0];
        snd_cq.put_cqe(temp_cqe);
        `uvm_info("NOTICE", "send_ref_cqe finished!", UVM_LOW);
    endtask: send_ref_cqe

    task send_mem_check(
        int host_id,
        int remote_host_id,
        bit [10:0] proc_id,
        bit [10:0] remote_proc_id,
        wqe input_wqe,
        e_op_type op_type,
        mpt local_mpt_que[$],
        mpt remote_mpt_que[$],
        hca_check_mem_list check_list
    );
        check_mem_unit check_unit;
        wqe_data_seg_unit temp_data_seg;
        addr offset = 0;
        mpt local_mpt;
        mpt remote_mpt;
        if (op_type == READ) begin
            while (input_wqe.data_seg.size() != 0) begin
                temp_data_seg = input_wqe.data_seg.pop_front();
                check_unit.src_host = remote_host_id;
                check_unit.dst_host = host_id;
                check_unit.length = temp_data_seg.byte_count;
                check_unit.src_addr = `PA(proc_id, input_wqe.raddr_seg.raddr) + offset;
                check_unit.dst_addr = `PA(proc_id, temp_data_seg.addr);
                `uvm_info("MEM_CHECK_NOTICE", $sformatf("send memory check unit, src_addr: %h, dst_addr: %h, operation type: %0d", 
                                                 check_unit.src_addr, check_unit.dst_addr, op_type), UVM_LOW);
                check_list.check_list[host_id].push_back(check_unit);
                offset += temp_data_seg.byte_count;
            end
        end
        else if (op_type == WRITE) begin
            while (input_wqe.data_seg.size() != 0) begin
                temp_data_seg = input_wqe.data_seg.pop_front();
                check_unit.src_host = host_id;
                check_unit.dst_host = remote_host_id;
                check_unit.length = temp_data_seg.byte_count;
                check_unit.src_addr = `PA(proc_id, temp_data_seg.addr);
                check_unit.dst_addr = `PA(proc_id, input_wqe.raddr_seg.raddr) + offset;
                `uvm_info("MEM_CHECK_NOTICE", $sformatf("send memory check unit, src_addr: %h, dst_addr: %h, operation type: %0d", 
                                                 check_unit.src_addr, check_unit.dst_addr, op_type), UVM_LOW);
                check_list.check_list[host_id].push_back(check_unit);
                offset += temp_data_seg.byte_count;
            end
        end
        else if (op_type == RECV) begin // WARNING
            while (input_wqe.data_seg.size() != 0) begin
                temp_data_seg = input_wqe.data_seg.pop_front();
                remote_mpt = remote_mpt_que.pop_front();
                local_mpt = local_mpt_que.pop_front();
                check_unit.src_host = remote_host_id;
                check_unit.dst_host = host_id;
                check_unit.length = temp_data_seg.byte_count;
                check_unit.src_addr = `PA(remote_proc_id, remote_mpt.start);
                check_unit.dst_addr = `PA(proc_id, local_mpt.start);
                `uvm_info("MEM_CHECK_NOTICE", $sformatf("send memory check unit, src_addr: %h, dst_addr: %h, operation type: %0d", 
                                                 check_unit.src_addr, check_unit.dst_addr, op_type), UVM_LOW);
                check_list.check_list[host_id].push_back(check_unit);
                offset += temp_data_seg.byte_count;
            end
        end
        else begin
            `uvm_fatal("OP_TYPE_ERR", "Illegal op_type!");
        end
    endtask: send_mem_check

    //------------------------------------------------------------------------------
    // task name     : write_wqe_to_mem
    // function      : write one wqe of an operation type into memory space of a 
    //                 given QP
    // invoked       : by put_wqe
    //------------------------------------------------------------------------------
    task write_wqe_to_mem(hca_queue_pair qp, wqe temp_wqe, e_op_type op_type, int sg_num); // write ONE wqe to memory
                                                                               // not support inline seg
        addr base_paddr;
        addr wqe_offset;
        bit [`DATA_WIDTH - 1 : 0] raw_data;
        wqe_data_seg_unit data_seg_unit;
        int beat_num;
        bit [10:0] proc_id;
        int host_id;
        hca_fifo #(.width(256)) data_fifo;
        proc_id = qp.proc_id;
        host_id = qp.host_id;

        data_fifo = hca_fifo#(.width(256))::type_id::create("data_fifo");

        // set wqe_offset and base physical address 
        if (op_type == RECV) begin
            base_paddr = `PA_QP(proc_id, qp.ctx.local_qpn) + `SQ_RQ_GAP;
            wqe_offset = qp.rq_header;
        end
        else begin
            base_paddr = `PA_QP(proc_id, qp.ctx.local_qpn);
            wqe_offset = qp.sq_header;
        end

        // write wqe
        if (op_type == WRITE || op_type == READ) begin
            raw_data = 0;
            data_fifo.clean();
            raw_data[127:0] = {
                temp_wqe.next_seg.imm_data,
                {28'b0}, temp_wqe.next_seg.cq, temp_wqe.next_seg.evt, temp_wqe.next_seg.solicit, 1'b0,
                temp_wqe.next_seg.next_ee, temp_wqe.next_seg.next_dbd, temp_wqe.next_seg.next_fence, temp_wqe.next_seg.next_wqe_size,
                temp_wqe.next_seg.next_wqe, 1'b0, temp_wqe.next_seg.next_opcode
            };
            raw_data[255:128] = {
                32'b0,
                temp_wqe.raddr_seg.rkey,
                temp_wqe.raddr_seg.raddr
            };
            data_fifo.push(trans2comb(raw_data));
            raw_data = 0;
            beat_num = 0;
            while (temp_wqe.data_seg.size() != 0) begin
                data_seg_unit = temp_wqe.data_seg.pop_front();
                if (beat_num % 2 == 0) begin
                    raw_data = 0;
                    raw_data[127:0] = {
                        data_seg_unit.addr,
                        data_seg_unit.lkey,
                        data_seg_unit.byte_count
                    };
                end
                else begin
                    raw_data[255:128] = {
                        data_seg_unit.addr,
                        data_seg_unit.lkey,
                        data_seg_unit.byte_count
                    };
                end
                if (temp_wqe.data_seg.size() == 0 || beat_num % 2 == 1) begin
                    data_fifo.push(trans2comb(raw_data));
                end
                beat_num++;
            end
            mem.write_block(base_paddr + wqe_offset, data_fifo, 32 + sg_num * 16);
        end
        else if (op_type == SEND) begin
            if (qp.ctx.flags[15:0] != `HGHCA_QP_ST_UD) begin // RC/UC
                raw_data = 0;
                data_fifo.clean();
                raw_data[127:0] = {
                    temp_wqe.next_seg.imm_data,
                    temp_wqe.next_seg.res_2, temp_wqe.next_seg.cq, temp_wqe.next_seg.evt, temp_wqe.next_seg.solicit, temp_wqe.next_seg.res_1,
                    temp_wqe.next_seg.next_ee, temp_wqe.next_seg.next_dbd, temp_wqe.next_seg.next_fence, temp_wqe.next_seg.next_wqe_size,
                    temp_wqe.next_seg.next_wqe, temp_wqe.next_seg.res_0, temp_wqe.next_seg.next_opcode
                };
                beat_num = 0;
                while (temp_wqe.data_seg.size() != 0) begin
                    data_seg_unit = temp_wqe.data_seg.pop_front();
                    if (beat_num % 2 == 0) begin
                        raw_data[255:128] = {
                            data_seg_unit.addr,
                            data_seg_unit.lkey,
                            data_seg_unit.byte_count
                        };
                        data_fifo.push(trans2comb(raw_data));
                    end
                    else begin
                        raw_data = 0;
                        raw_data[127:0] = {
                            data_seg_unit.addr,
                            data_seg_unit.lkey,
                            data_seg_unit.byte_count
                        };
                        if (temp_wqe.data_seg.size() == 0) begin
                            data_fifo.push(trans2comb(raw_data));
                        end
                    end
                    beat_num++;
                end
                mem.write_block(base_paddr + wqe_offset, data_fifo, 16 + sg_num * 16);
            end
            else if (qp.ctx.flags[15:0] == `HGHCA_QP_ST_UD) begin
                raw_data = 0;
                data_fifo.clean();
                raw_data[127:0] = {
                    temp_wqe.next_seg.imm_data,
                    temp_wqe.next_seg.res_2, temp_wqe.next_seg.cq, temp_wqe.next_seg.evt, temp_wqe.next_seg.solicit, temp_wqe.next_seg.res_1,
                    temp_wqe.next_seg.next_ee, temp_wqe.next_seg.next_dbd, temp_wqe.next_seg.next_fence, temp_wqe.next_seg.next_wqe_size,
                    temp_wqe.next_seg.next_wqe, temp_wqe.next_seg.res_0, temp_wqe.next_seg.next_opcode
                };
                raw_data[255:128] = {
                    temp_wqe.ud_seg.dmac[47:16],
                    temp_wqe.ud_seg.smac[47:16],
                    temp_wqe.ud_seg.dmac[15:0], temp_wqe.ud_seg.smac[15:0],
                    96'b0, temp_wqe.ud_seg.port
                };
                data_fifo.push(trans2comb(raw_data));
                raw_data = {
                    32'b0,
                    32'b0,
                    temp_wqe.ud_seg.qkey,
                    temp_wqe.ud_seg.dqpn,
                    32'b0,
                    32'b0,
                    temp_wqe.ud_seg.dip,
                    temp_wqe.ud_seg.sip
                };
                data_fifo.push(trans2comb(raw_data));
                beat_num = 0;
                while (temp_wqe.data_seg.size() != 0) begin
                    data_seg_unit = temp_wqe.data_seg.pop_front();
                    if (beat_num % 2 == 0) begin
                        raw_data = 0;
                        raw_data[127:0] = {
                            data_seg_unit.addr,
                            data_seg_unit.lkey,
                            data_seg_unit.byte_count
                        };
                    end
                    else begin
                        raw_data[255:128] = {
                            data_seg_unit.addr,
                            data_seg_unit.lkey,
                            data_seg_unit.byte_count
                        };
                    end
                    if (temp_wqe.data_seg.size() == 0 || beat_num % 2 == 1) begin
                        data_fifo.push(trans2comb(raw_data));
                    end
                    beat_num++;
                end
                mem.write_block(base_paddr + wqe_offset, data_fifo, 32 + sg_num * 16);
            end
        end
        else if (op_type == RECV) begin
            if (qp.ctx.flags[15:0] != `HGHCA_QP_ST_UD) begin
                raw_data = 0;
                data_fifo.clean();
                raw_data[127:0] = {
                    temp_wqe.next_seg.imm_data,
                    temp_wqe.next_seg.res_2, temp_wqe.next_seg.cq, temp_wqe.next_seg.evt, temp_wqe.next_seg.solicit, temp_wqe.next_seg.res_1,
                    temp_wqe.next_seg.next_ee, temp_wqe.next_seg.next_dbd, temp_wqe.next_seg.next_fence, temp_wqe.next_seg.next_wqe_size,
                    temp_wqe.next_seg.next_wqe, temp_wqe.next_seg.res_0, temp_wqe.next_seg.next_opcode
                };
                beat_num = 0;
                while (temp_wqe.data_seg.size() != 0) begin
                    data_seg_unit = temp_wqe.data_seg.pop_front();
                    if (beat_num % 2 == 0) begin
                        raw_data[255:128] = {
                            data_seg_unit.addr,
                            data_seg_unit.lkey,
                            data_seg_unit.byte_count
                        };
                        data_fifo.push(trans2comb(raw_data));
                    end
                    else begin
                        raw_data = 0;
                        raw_data[127:0] = {
                            data_seg_unit.addr,
                            data_seg_unit.lkey,
                            data_seg_unit.byte_count
                        };
                        if (temp_wqe.data_seg.size() != 0) begin
                            data_fifo.push(trans2comb(raw_data));
                        end
                    end
                    beat_num++;
                end
                raw_data = 0;
                raw_data[127:0] = temp_wqe.zero_seg.zero;
                data_fifo.push(trans2comb(raw_data));
                mem.write_block(base_paddr + wqe_offset, data_fifo, 32 + sg_num * 16);
            end
            else if (qp.ctx.flags[15:0] == `HGHCA_QP_ST_UD) begin
                raw_data = 0;
                data_fifo.clean();
                raw_data[127:0] = {
                    temp_wqe.next_seg.imm_data,
                    temp_wqe.next_seg.res_2, temp_wqe.next_seg.cq, temp_wqe.next_seg.evt, temp_wqe.next_seg.solicit, temp_wqe.next_seg.res_1,
                    temp_wqe.next_seg.next_ee, temp_wqe.next_seg.next_dbd, temp_wqe.next_seg.next_fence, temp_wqe.next_seg.next_wqe_size,
                    temp_wqe.next_seg.next_wqe, temp_wqe.next_seg.res_0, temp_wqe.next_seg.next_opcode
                };
                raw_data[255:128] = {
                    temp_wqe.ud_seg.dmac[47:16],
                    temp_wqe.ud_seg.smac[47:16],
                    temp_wqe.ud_seg.dmac[15:0], temp_wqe.ud_seg.smac[15:0],
                    96'b0, temp_wqe.ud_seg.port
                };
                data_fifo.push(trans2comb(raw_data));
                raw_data = {
                    32'b0,
                    32'b0,
                    temp_wqe.ud_seg.qkey,
                    temp_wqe.ud_seg.dqpn,
                    32'b0,
                    32'b0,
                    temp_wqe.ud_seg.dip,
                    temp_wqe.ud_seg.sip
                };
                data_fifo.push(trans2comb(raw_data));
                beat_num = 0;
                while (temp_wqe.data_seg.size() != 0) begin
                    data_seg_unit = temp_wqe.data_seg.pop_front();
                    if (beat_num % 2 == 0) begin
                        raw_data = 0;
                        raw_data[127:0] = {
                            data_seg_unit.addr,
                            data_seg_unit.lkey,
                            data_seg_unit.byte_count
                        };
                    end
                    else begin
                        raw_data[255:128] = {
                            data_seg_unit.addr,
                            data_seg_unit.lkey,
                            data_seg_unit.byte_count
                        };
                    end
                    if (temp_wqe.data_seg.size() == 0 || beat_num % 2 == 1) begin
                        data_fifo.push(trans2comb(raw_data));
                    end
                    beat_num++;
                end
                raw_data = 0;
                raw_data[127:0] = temp_wqe.zero_seg.zero;
                data_fifo.push(trans2comb(raw_data));
                mem.write_block(base_paddr + wqe_offset, data_fifo, 48 + sg_num * 16);
            end
        end
        `uvm_info("MEM_INFO", $sformatf("write wqe finished, host_id: %h, addr: %h, op_type: %h", qp.host_id, base_paddr + wqe_offset, op_type), UVM_LOW);
    endtask: write_wqe_to_mem

    //------------------------------------------------------------------------------
    // function name : trans2comb
    // function      : transfer an array to an combination array which can be used 
    //                 in hca_fifo
    // invoked       : by user
    //------------------------------------------------------------------------------
    function bit [256/`BYTE_BIT_WIDTH-1:0][`BYTE_BIT_WIDTH-1:0] trans2comb(bit [255:0] raw_data);
        bit [256/`BYTE_BIT_WIDTH-1:0][`BYTE_BIT_WIDTH-1:0] result;
        for (int i = 0; i < 32; i++) begin
            result[i] = raw_data[i * 8 + 7 -: 8];
        end
        return result;
    endfunction: trans2comb

    //------------------------------------------------------------------------------
    // function name : consume_wqe
    // function      : update tail pointer, 0: SQ, 1: RQ
    // invoked       : by user
    //------------------------------------------------------------------------------
    function consume_wqe(bit queue);
        // set WQE length
        addr desc_byte_len;
        desc_byte_len = 0;
        if (queue == 0) begin
            desc_byte_len[ctx.sq_entry_sz_log] = 1'b1;
            sq_tail = sq_tail + desc_byte_len;
            if (sq_tail > sq_header) begin
                `uvm_fatal("QUE_ERR", $sformatf("sq_tail exceeds sq_header! qpn: %h, sq_tail: %h, sq_header: %h", ctx.local_qpn, sq_tail, sq_header));
            end
        end
        else begin
            desc_byte_len[ctx.rq_entry_sz_log] = 1'b1;
            rq_tail = rq_tail + desc_byte_len;
            if (rq_tail > rq_header) begin
                `uvm_fatal("QUE_ERR", $sformatf("rq_tail exceeds rq_header! qpn: %h, rq_tail: %h, rq_header: %h", ctx.local_qpn, rq_tail, rq_header));
            end
        end
    endfunction: consume_wqe
endclass: hca_queue_pair
`endif