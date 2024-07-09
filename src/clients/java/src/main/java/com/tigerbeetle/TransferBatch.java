//////////////////////////////////////////////////////////
// This file was auto-generated by java_bindings.zig
// Do not manually modify.
//////////////////////////////////////////////////////////

package com.tigerbeetle;

import java.nio.ByteBuffer;
import java.math.BigInteger;

public final class TransferBatch extends Batch {

    interface Struct {
        int SIZE = 128;

        int Id = 0;
        int DebitAccountId = 16;
        int CreditAccountId = 32;
        int Amount = 48;
        int PendingId = 64;
        int UserData128 = 80;
        int UserData64 = 96;
        int UserData32 = 104;
        int Timeout = 108;
        int Ledger = 112;
        int Code = 116;
        int Flags = 118;
        int Timestamp = 120;
    }

    static final TransferBatch EMPTY = new TransferBatch(0);

    /**
     * Creates an empty batch with the desired maximum capacity.
     * <p>
     * Once created, an instance cannot be resized, however it may contain any number of elements
     * between zero and its {@link #getCapacity capacity}.
     *
     * @param capacity the maximum capacity.
     * @throws IllegalArgumentException if capacity is negative.
     */
    public TransferBatch(final int capacity) {
        super(capacity, Struct.SIZE);
    }

    TransferBatch(final ByteBuffer buffer) {
        super(buffer, Struct.SIZE);
    }

    /**
     * @return an array of 16 bytes representing the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#id">id</a>
     */
    public byte[] getId() {
        return getUInt128(at(Struct.Id));
    }

    /**
     * @param part a {@link UInt128} enum indicating which part of the 128-bit value
              is to be retrieved.
     * @return a {@code long} representing the first 8 bytes of the 128-bit value if
     *         {@link UInt128#LeastSignificant} is informed, or the last 8 bytes if
     *         {@link UInt128#MostSignificant}.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#id">id</a>
     */
    public long getId(final UInt128 part) {
        return getUInt128(at(Struct.Id), part);
    }

    /**
     * @param id an array of 16 bytes representing the 128-bit value.
     * @throws IllegalArgumentException if {@code id} is not 16 bytes long.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#id">id</a>
     */
    public void setId(final byte[] id) {
        putUInt128(at(Struct.Id), id);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @param mostSignificant a {@code long} representing the last 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#id">id</a>
     */
    public void setId(final long leastSignificant, final long mostSignificant) {
        putUInt128(at(Struct.Id), leastSignificant, mostSignificant);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#id">id</a>
     */
    public void setId(final long leastSignificant) {
        putUInt128(at(Struct.Id), leastSignificant, 0);
    }

    /**
     * @return an array of 16 bytes representing the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#debit_account_id">debit_account_id</a>
     */
    public byte[] getDebitAccountId() {
        return getUInt128(at(Struct.DebitAccountId));
    }

    /**
     * @param part a {@link UInt128} enum indicating which part of the 128-bit value
              is to be retrieved.
     * @return a {@code long} representing the first 8 bytes of the 128-bit value if
     *         {@link UInt128#LeastSignificant} is informed, or the last 8 bytes if
     *         {@link UInt128#MostSignificant}.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#debit_account_id">debit_account_id</a>
     */
    public long getDebitAccountId(final UInt128 part) {
        return getUInt128(at(Struct.DebitAccountId), part);
    }

    /**
     * @param debitAccountId an array of 16 bytes representing the 128-bit value.
     * @throws IllegalArgumentException if {@code debitAccountId} is not 16 bytes long.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#debit_account_id">debit_account_id</a>
     */
    public void setDebitAccountId(final byte[] debitAccountId) {
        putUInt128(at(Struct.DebitAccountId), debitAccountId);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @param mostSignificant a {@code long} representing the last 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#debit_account_id">debit_account_id</a>
     */
    public void setDebitAccountId(final long leastSignificant, final long mostSignificant) {
        putUInt128(at(Struct.DebitAccountId), leastSignificant, mostSignificant);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#debit_account_id">debit_account_id</a>
     */
    public void setDebitAccountId(final long leastSignificant) {
        putUInt128(at(Struct.DebitAccountId), leastSignificant, 0);
    }

    /**
     * @return an array of 16 bytes representing the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#credit_account_id">credit_account_id</a>
     */
    public byte[] getCreditAccountId() {
        return getUInt128(at(Struct.CreditAccountId));
    }

    /**
     * @param part a {@link UInt128} enum indicating which part of the 128-bit value
              is to be retrieved.
     * @return a {@code long} representing the first 8 bytes of the 128-bit value if
     *         {@link UInt128#LeastSignificant} is informed, or the last 8 bytes if
     *         {@link UInt128#MostSignificant}.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#credit_account_id">credit_account_id</a>
     */
    public long getCreditAccountId(final UInt128 part) {
        return getUInt128(at(Struct.CreditAccountId), part);
    }

    /**
     * @param creditAccountId an array of 16 bytes representing the 128-bit value.
     * @throws IllegalArgumentException if {@code creditAccountId} is not 16 bytes long.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#credit_account_id">credit_account_id</a>
     */
    public void setCreditAccountId(final byte[] creditAccountId) {
        putUInt128(at(Struct.CreditAccountId), creditAccountId);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @param mostSignificant a {@code long} representing the last 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#credit_account_id">credit_account_id</a>
     */
    public void setCreditAccountId(final long leastSignificant, final long mostSignificant) {
        putUInt128(at(Struct.CreditAccountId), leastSignificant, mostSignificant);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#credit_account_id">credit_account_id</a>
     */
    public void setCreditAccountId(final long leastSignificant) {
        putUInt128(at(Struct.CreditAccountId), leastSignificant, 0);
    }

    /**
     * @return a {@link java.math.BigInteger} representing the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#amount">amount</a>
     */
    public BigInteger getAmount() {
        final var index = at(Struct.Amount);
        return UInt128.asBigInteger(
            getUInt128(index, UInt128.LeastSignificant),
            getUInt128(index, UInt128.MostSignificant));
    }

    /**
     * @param part a {@link UInt128} enum indicating which part of the 128-bit value
              is to be retrieved.
     * @return a {@code long} representing the first 8 bytes of the 128-bit value if
     *         {@link UInt128#LeastSignificant} is informed, or the last 8 bytes if
     *         {@link UInt128#MostSignificant}.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#amount">amount</a>
     */
    public long getAmount(final UInt128 part) {
        return getUInt128(at(Struct.Amount), part);
    }

    /**
     * @param amount a {@link java.math.BigInteger} representing the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#amount">amount</a>
     */
    public void setAmount(final BigInteger amount) {
        putUInt128(at(Struct.Amount), UInt128.asBytes(amount));
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @param mostSignificant a {@code long} representing the last 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#amount">amount</a>
     */
    public void setAmount(final long leastSignificant, final long mostSignificant) {
        putUInt128(at(Struct.Amount), leastSignificant, mostSignificant);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#amount">amount</a>
     */
    public void setAmount(final long leastSignificant) {
        putUInt128(at(Struct.Amount), leastSignificant, 0);
    }

    /**
     * @return an array of 16 bytes representing the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#pending_id">pending_id</a>
     */
    public byte[] getPendingId() {
        return getUInt128(at(Struct.PendingId));
    }

    /**
     * @param part a {@link UInt128} enum indicating which part of the 128-bit value
              is to be retrieved.
     * @return a {@code long} representing the first 8 bytes of the 128-bit value if
     *         {@link UInt128#LeastSignificant} is informed, or the last 8 bytes if
     *         {@link UInt128#MostSignificant}.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#pending_id">pending_id</a>
     */
    public long getPendingId(final UInt128 part) {
        return getUInt128(at(Struct.PendingId), part);
    }

    /**
     * @param pendingId an array of 16 bytes representing the 128-bit value.
     * @throws IllegalArgumentException if {@code pendingId} is not 16 bytes long.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#pending_id">pending_id</a>
     */
    public void setPendingId(final byte[] pendingId) {
        putUInt128(at(Struct.PendingId), pendingId);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @param mostSignificant a {@code long} representing the last 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#pending_id">pending_id</a>
     */
    public void setPendingId(final long leastSignificant, final long mostSignificant) {
        putUInt128(at(Struct.PendingId), leastSignificant, mostSignificant);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#pending_id">pending_id</a>
     */
    public void setPendingId(final long leastSignificant) {
        putUInt128(at(Struct.PendingId), leastSignificant, 0);
    }

    /**
     * @return an array of 16 bytes representing the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#user_data_128">user_data_128</a>
     */
    public byte[] getUserData128() {
        return getUInt128(at(Struct.UserData128));
    }

    /**
     * @param part a {@link UInt128} enum indicating which part of the 128-bit value
              is to be retrieved.
     * @return a {@code long} representing the first 8 bytes of the 128-bit value if
     *         {@link UInt128#LeastSignificant} is informed, or the last 8 bytes if
     *         {@link UInt128#MostSignificant}.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#user_data_128">user_data_128</a>
     */
    public long getUserData128(final UInt128 part) {
        return getUInt128(at(Struct.UserData128), part);
    }

    /**
     * @param userData128 an array of 16 bytes representing the 128-bit value.
     * @throws IllegalArgumentException if {@code userData128} is not 16 bytes long.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#user_data_128">user_data_128</a>
     */
    public void setUserData128(final byte[] userData128) {
        putUInt128(at(Struct.UserData128), userData128);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @param mostSignificant a {@code long} representing the last 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#user_data_128">user_data_128</a>
     */
    public void setUserData128(final long leastSignificant, final long mostSignificant) {
        putUInt128(at(Struct.UserData128), leastSignificant, mostSignificant);
    }

    /**
     * @param leastSignificant a {@code long} representing the first 8 bytes of the 128-bit value.
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#user_data_128">user_data_128</a>
     */
    public void setUserData128(final long leastSignificant) {
        putUInt128(at(Struct.UserData128), leastSignificant, 0);
    }

    /**
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#user_data_64">user_data_64</a>
     */
    public long getUserData64() {
        final var value = getUInt64(at(Struct.UserData64));
        return value;
    }

    /**
     * @param userData64
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#user_data_64">user_data_64</a>
     */
    public void setUserData64(final long userData64) {
        putUInt64(at(Struct.UserData64), userData64);
    }

    /**
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#user_data_32">user_data_32</a>
     */
    public int getUserData32() {
        final var value = getUInt32(at(Struct.UserData32));
        return value;
    }

    /**
     * @param userData32
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#user_data_32">user_data_32</a>
     */
    public void setUserData32(final int userData32) {
        putUInt32(at(Struct.UserData32), userData32);
    }

    /**
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#timeout">timeout</a>
     */
    public int getTimeout() {
        final var value = getUInt32(at(Struct.Timeout));
        return value;
    }

    /**
     * @param timeout
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#timeout">timeout</a>
     */
    public void setTimeout(final int timeout) {
        putUInt32(at(Struct.Timeout), timeout);
    }

    /**
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#ledger">ledger</a>
     */
    public int getLedger() {
        final var value = getUInt32(at(Struct.Ledger));
        return value;
    }

    /**
     * @param ledger
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#ledger">ledger</a>
     */
    public void setLedger(final int ledger) {
        putUInt32(at(Struct.Ledger), ledger);
    }

    /**
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#code">code</a>
     */
    public int getCode() {
        final var value = getUInt16(at(Struct.Code));
        return value;
    }

    /**
     * @param code
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#code">code</a>
     */
    public void setCode(final int code) {
        putUInt16(at(Struct.Code), code);
    }

    /**
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#flags">flags</a>
     */
    public int getFlags() {
        final var value = getUInt16(at(Struct.Flags));
        return value;
    }

    /**
     * @param flags
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#flags">flags</a>
     */
    public void setFlags(final int flags) {
        putUInt16(at(Struct.Flags), flags);
    }

    /**
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#timestamp">timestamp</a>
     */
    public long getTimestamp() {
        final var value = getUInt64(at(Struct.Timestamp));
        return value;
    }

    /**
     * @param timestamp
     * @throws IllegalStateException if not at a {@link #isValidPosition valid position}.
     * @throws IllegalStateException if a {@link #isReadOnly() read-only} batch.
     * @see <a href="https://docs.tigerbeetle.com/reference/transfer#timestamp">timestamp</a>
     */
    void setTimestamp(final long timestamp) {
        putUInt64(at(Struct.Timestamp), timestamp);
    }

}

